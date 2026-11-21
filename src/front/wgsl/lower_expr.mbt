// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Lowers an expression, returning the handle of either a value or a pointer.
/// The caller decides which of the two it needs; a variable name, for instance,
/// is a pointer, and reading it is what makes it a value.
fn Builder::lower_expr(
  self : Builder,
  expr : Expr,
) -> @moonnaga.Handle raise Failed {
  match expr {
    Number(number, span) => {
      let (literal, scalar) = literal_of_number(number, span)
      let ty = self.types.scalar_type(scalar)
      self.emit(@moonnaga.Literal(literal), Plain(ty))
    }
    Bool(value, _) => {
      let ty = self.types.scalar_type(@moonnaga.boolean())
      self.emit(@moonnaga.Literal(@moonnaga.Bool(value)), Plain(ty))
    }
    Ident(name, span) => self.lower_ident(name, span)
    UnaryApply(op, inner, span) => self.lower_unary(op, inner, span)
    BinaryApply(op, left, right, span) =>
      self.lower_binary(op, left, right, span)
    Invoke(name, args, call_args, span) =>
      self.lower_call(name, args, call_args, span)
    Bitcast(args, inner, span) => self.lower_bitcast(args, inner, span)
    Index(base, index, span) => self.lower_index(base, index, span)
    Member(base, field, span) => self.lower_member(base, field, span)
  }
}

///|
/// The value of an expression, loading it first when it is a reference.
fn Builder::lower_value(
  self : Builder,
  expr : Expr,
) -> @moonnaga.Handle raise Failed {
  let handle = self.lower_expr(expr)
  self.as_value(handle)
}

///|
fn Builder::lower_ident(
  self : Builder,
  name : String,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match self.lookup(name) {
    Some(binding) =>
      match binding {
        Value(handle, _) => handle
        Local(variable, ty) =>
          self.emit(
            @moonnaga.LocalVariable(variable),
            Reference(ty, @moonnaga.Function),
          )
        Global(variable, ty, space) =>
          self.emit(@moonnaga.GlobalVariable(variable), Reference(ty, space))
        Constant(constant, ty) =>
          self.emit(@moonnaga.Constant(constant), Plain(ty))
        Override(over, ty) => self.emit(@moonnaga.Override(over), Plain(ty))
      }
    None =>
      match self.consts.get(name) {
        Some(entry) =>
          self.emit(@moonnaga.Constant(entry.handle), Plain(entry.ty))
        None =>
          match self.override_names.get(name) {
            Some(over) => {
              let ty = self.shader().overrides.get(over).ty
              self.emit(@moonnaga.Override(over), Plain(ty))
            }
            None =>
              match self.globals.get(name) {
                Some(variable) => {
                  let global = self.shader().global_variables.get(variable)
                  if global.space == @moonnaga.Handle {
                    // A `var` in the handle space is read as the image or
                    // sampler it names, not as a pointer to one.
                    self.emit(
                      @moonnaga.GlobalVariable(variable),
                      Plain(global.ty),
                    )
                  } else {
                    self.emit(
                      @moonnaga.GlobalVariable(variable),
                      Reference(global.ty, global.space),
                    )
                  }
                }
                None => fail("`\{name}` is not declared", span)
              }
          }
      }
  }
}

///|
fn Builder::lower_unary(
  self : Builder,
  op : UnaryOp,
  inner : Expr,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match op {
    Deref => {
      let handle = self.lower_expr(inner)
      match self.kind_of(handle) {
        Reference(_, _) => handle
        Plain(_) => fail("`*` needs a pointer", span)
      }
    }
    AddressOf => {
      let handle = self.lower_expr(inner)
      match self.kind_of(handle) {
        Reference(_, _) => handle
        Plain(_) => fail("`&` needs a reference", span)
      }
    }
    Negate | LogicalNot | BitwiseNot => {
      let value = self.lower_value(inner)
      let ty = self.type_of(value)
      let operator = match op {
        Negate => @moonnaga.Negate
        LogicalNot => @moonnaga.LogicalNot
        _ => @moonnaga.BitwiseNot
      }
      self.emit(@moonnaga.Unary({ op: operator, expr: value, }), Plain(ty))
    }
  }
}

///|
/// Brings two operands to one type: an abstract literal takes the type of the
/// other side, and two abstract operands stay abstract until something concrete
/// looks at them.
fn Builder::coerce_pair(
  self : Builder,
  left : @moonnaga.Handle,
  right : @moonnaga.Handle,
) -> Unit {
  let left_ty = self.type_of(left)
  let right_ty = self.type_of(right)
  if left_ty == right_ty {
    return
  }
  let left_scalar = self.shader().scalar_of(left_ty)
  let right_scalar = self.shader().scalar_of(right_ty)
  match (left_scalar, right_scalar) {
    (Some(left_scalar), Some(right_scalar)) =>
      if left_scalar.is_abstract() && !right_scalar.is_abstract() {
        self.coerce(left, right_ty)
      } else if right_scalar.is_abstract() && !left_scalar.is_abstract() {
        self.coerce(right, left_ty)
      } else if left_scalar.is_abstract() && right_scalar.is_abstract() {
        if left_scalar.kind == AbstractFloat ||
          right_scalar.kind == AbstractFloat {
          let float_ty = self.types.scalar_type(
            @moonnaga.Scalar::new(AbstractFloat, 8),
          )
          self.coerce(left, float_ty)
          self.coerce(right, float_ty)
        }
      }
    _ => ()
  }
}

///|
fn Builder::lower_binary(
  self : Builder,
  op : BinaryOp,
  left_expr : Expr,
  right_expr : Expr,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let mut left = self.lower_value(left_expr)
  let mut right = self.lower_value(right_expr)
  self.coerce_pair(left, right)
  // A scalar next to a vector is a splat: `2.0 + v` means `vec4(2.0) + v`.
  match
    (
      self.shader().components_of(self.type_of(left)),
      self.shader().components_of(self.type_of(right)),
    ) {
    (Some(1), Some(count)) =>
      if count > 1 {
        let target = self.type_of(right)
        if self.scalar_kind_matches(self.type_of(left), target) {
          left = self.splat_to(left, target)
        }
      }
    (Some(count), Some(1)) =>
      if count > 1 {
        let target = self.type_of(left)
        if self.scalar_kind_matches(self.type_of(right), target) {
          right = self.splat_to(right, target)
        }
      }
    _ => ()
  }
  let left_ty = self.type_of(left)
  let right_ty = self.type_of(right)
  let operator = match op {
    Add => @moonnaga.BinaryOperator::Add
    Subtract => @moonnaga.BinaryOperator::Subtract
    Multiply => @moonnaga.BinaryOperator::Multiply
    Divide => @moonnaga.BinaryOperator::Divide
    Modulo => @moonnaga.BinaryOperator::Modulo
    Equal => @moonnaga.BinaryOperator::Equal
    NotEqual => @moonnaga.BinaryOperator::NotEqual
    Less => @moonnaga.BinaryOperator::Less
    LessEqual => @moonnaga.BinaryOperator::LessEqual
    Greater => @moonnaga.BinaryOperator::Greater
    GreaterEqual => @moonnaga.BinaryOperator::GreaterEqual
    And => @moonnaga.BinaryOperator::And
    Or => @moonnaga.BinaryOperator::InclusiveOr
    Xor => @moonnaga.BinaryOperator::ExclusiveOr
    LogicalAnd => @moonnaga.BinaryOperator::LogicalAnd
    LogicalOr => @moonnaga.BinaryOperator::LogicalOr
    ShiftLeft => @moonnaga.BinaryOperator::ShiftLeft
    ShiftRight => @moonnaga.BinaryOperator::ShiftRight
  }
  let result_ty = match op {
    Equal | NotEqual | Less | LessEqual | Greater | GreaterEqual =>
      self.comparison_result(left_ty, span)
    LogicalAnd | LogicalOr => left_ty
    ShiftLeft | ShiftRight => left_ty
    Multiply => self.multiply_result(left_ty, right_ty, span)
    _ => left_ty
  }
  self.emit(@moonnaga.Binary({ op: operator, left, right, }), Plain(result_ty))
}

///|
/// A comparison of vectors gives a vector of booleans of the same width.
fn Builder::comparison_result(
  self : Builder,
  operand : @moonnaga.Handle,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match self.shader().type_inner(operand) {
    Scalar(_) => self.types.scalar_type(@moonnaga.boolean())
    Vector(vector) => self.types.vector_type(vector.size, @moonnaga.boolean())
    _ => fail("a comparison needs scalars or vectors", span)
  }
}

///|
/// The type a multiplication produces, which matrix products change: a
/// `matCxR` times a `vecC` is a `vecR`, and two matrices compose their shapes.
fn Builder::multiply_result(
  self : Builder,
  left : @moonnaga.Handle,
  right : @moonnaga.Handle,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let left_inner = self.shader().type_inner(left)
  let right_inner = self.shader().type_inner(right)
  match (left_inner, right_inner) {
    (Matrix(matrix), Vector(_vector)) =>
      self.types.vector_type(matrix.rows, matrix.scalar)
    (Vector(vector), Matrix(matrix)) =>
      if vector.size == matrix.rows {
        self.types.vector_type(matrix.columns, matrix.scalar)
      } else {
        fail("the vector and the matrix do not fit", span)
      }
    (Matrix(left_matrix), Matrix(right_matrix)) =>
      if left_matrix.rows == right_matrix.columns {
        self.types.matrix_type(
          left_matrix.columns,
          right_matrix.rows,
          left_matrix.scalar,
        )
      } else {
        fail("the matrices do not fit", span)
      }
    (Matrix(_), Scalar(_)) => left
    (Scalar(_), Matrix(_)) => right
    (Vector(_), Scalar(_)) => left
    (Scalar(_), Vector(_)) => right
    _ => left
  }
}

///|
fn Builder::lower_index(
  self : Builder,
  base_expr : Expr,
  index_expr : Expr,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let base = self.lower_expr(base_expr)
  let index = self.lower_value(index_expr)
  let (container, space) = match self.kind_of(base) {
    Reference(ty, space) => (ty, Some(space))
    Plain(ty) => (ty, None)
  }
  let element = self.index_element(container, span)
  let result = match space {
    Some(space) => Reference(element, space)
    None => Plain(element)
  }
  match index_literal(self.exprs.get(index)) {
    Some(constant_index) =>
      self.emit(@moonnaga.AccessIndex({ base, index: constant_index, }), result)
    None => self.emit(@moonnaga.Access({ base, index, }), result)
  }
}

///|
/// The type one element of an indexable type has.
fn Builder::index_element(
  self : Builder,
  container : @moonnaga.Handle,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match self.shader().type_inner(container) {
    Array(array) => array.base
    Vector(vector) => self.types.scalar_type(vector.scalar)
    Matrix(matrix) => self.types.vector_type(matrix.rows, matrix.scalar)
    BindingArray(array) => array.base
    _ => fail("this value cannot be indexed", span)
  }
}

///|
/// The index of an `@moonnaga.AccessIndex`, when the index is a literal the module can
/// fold; otherwise the access stays dynamic.
fn index_literal(expr : @moonnaga.Expression) -> Int32? {
  match expr {
    @moonnaga.Literal(AbstractInt(value)) => Some(value.to_int())
    @moonnaga.Literal(I32(value)) => Some(value)
    @moonnaga.Literal(U32(value)) => Some(value.reinterpret_as_int())
    _ => None
  }
}

///|
fn Builder::lower_member(
  self : Builder,
  base_expr : Expr,
  field : String,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let base = self.lower_expr(base_expr)
  let (container, space) = match self.kind_of(base) {
    Reference(ty, space) => (ty, Some(space))
    Plain(ty) => (ty, None)
  }
  match self.shader().type_inner(container) {
    Struct(structure) => {
      let mut found = None
      for index in 0..<structure.members.length() {
        if structure.members[index].name == field {
          found = Some(index)
        }
      }
      match found {
        Some(index) => {
          let member_ty = structure.members[index].ty
          let result = match space {
            Some(space) => Reference(member_ty, space)
            None => Plain(member_ty)
          }
          self.emit(@moonnaga.AccessIndex({ base, index, }), result)
        }
        None => fail("`\{field}` is not a field of this struct", span)
      }
    }
    Vector(vector) => {
      let pattern = swizzle_pattern(field, span)
      if pattern.length() == 1 {
        let result = match space {
          Some(space) => Reference(self.types.scalar_type(vector.scalar), space)
          None => Plain(self.types.scalar_type(vector.scalar))
        }
        self.emit(
          @moonnaga.AccessIndex({ base, index: pattern[0].to_int(), }),
          result,
        )
      } else {
        let size = match @moonnaga.VectorSize::from_int(pattern.length()) {
          Some(size) => size
          None => fail("a swizzle has two, three or four components", span)
        }
        let ty = self.types.vector_type(size, vector.scalar)
        self.emit(
          @moonnaga.Swizzle({ size, vector: base, pattern, }),
          Plain(ty),
        )
      }
    }
    _ => fail("`\{field}` is not a field of this value", span)
  }
}

///|
/// The components a swizzle names. WGSL spells them `xyzw` and `rgba`, and a
/// swizzle may not mix the two spellings.
fn swizzle_pattern(
  field : String,
  span : @moonnaga.Span,
) -> Array[@moonnaga.SwizzleComponent] raise Failed {
  let pattern = []
  let mut first_is_colour = None
  for ch in field {
    let component = match ch {
      'x' => Some((@moonnaga.SwizzleComponent::X, false))
      'y' => Some((@moonnaga.SwizzleComponent::Y, false))
      'z' => Some((@moonnaga.SwizzleComponent::Z, false))
      'w' => Some((@moonnaga.SwizzleComponent::W, false))
      'r' => Some((@moonnaga.SwizzleComponent::X, true))
      'g' => Some((@moonnaga.SwizzleComponent::Y, true))
      'b' => Some((@moonnaga.SwizzleComponent::Z, true))
      'a' => Some((@moonnaga.SwizzleComponent::W, true))
      _ => None
    }
    match component {
      Some((component, is_colour)) => {
        match first_is_colour {
          None => first_is_colour = Some(is_colour)
          Some(first) =>
            if first != is_colour {
              fail("a swizzle cannot mix `xyzw` and `rgba`", span)
            }
        }
        pattern.push(component)
      }
      None => fail("`\{field}` is not a swizzle", span)
    }
  }
  pattern
}

///|
/// Whether two scalar-or-vector types share a scalar kind, which is what decides
/// whether one may be splatted into the other.
fn Builder::scalar_kind_matches(
  self : Builder,
  source : @moonnaga.Handle,
  target : @moonnaga.Handle,
) -> Bool {
  match (self.shader().scalar_of(source), self.shader().scalar_of(target)) {
    (Some(a), Some(b)) => a.kind == b.kind || a.is_abstract()
    _ => false
  }
}

///|
/// The expression repeated across a vector's components.
fn Builder::splat_to(
  self : Builder,
  value : @moonnaga.Handle,
  target : @moonnaga.Handle,
) -> @moonnaga.Handle {
  match self.shader().type_inner(target) {
    Vector(vector) => {
      let scalar_ty = self.types.scalar_type(vector.scalar)
      self.coerce(value, scalar_ty)
      self.emit(Splat({ size: vector.size, value, }), Plain(target))
    }
    _ => value
  }
}
