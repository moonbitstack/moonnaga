// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Works out the value of a constant expression, as far as the front end needs
/// one: array lengths, `case` labels, workgroup sizes and `const_assert`.
///
/// This is not the general constant evaluator a back end would want — it does
/// not fold inside function bodies, and it stops at anything it cannot see
/// through — but every use it has is one where the answer must be known before
/// the module is finished.
fn Builder::fold(self : Builder, handle : @moonnaga.Handle) -> ConstValue? {
  self.fold_expr(self.exprs.get(handle))
}

///|
fn Builder::fold_expr(
  self : Builder,
  expr : @moonnaga.Expression,
) -> ConstValue? {
  match expr {
    @moonnaga.Literal(literal) =>
      match literal {
        AbstractInt(value) => Some(Int(value))
        I32(value) => Some(Int(value.to_int64()))
        U32(value) => Some(Int(value.to_uint64().reinterpret_as_int64()))
        I64(value) => Some(Int(value))
        U64(value) => Some(Int(value.reinterpret_as_int64()))
        AbstractFloat(value) => Some(Float(value))
        F32(value) => Some(Float(value.to_double()))
        F64(value) => Some(Float(value))
        Bool(value) => Some(Bool(value))
      }
    @moonnaga.Constant(constant) => self.fold_constant(constant)
    @moonnaga.ZeroValue(ty) => Some(self.zero_of(ty))
    @moonnaga.Compose(compose) => {
      let values = []
      for component in compose.components {
        match self.fold(component) {
          Some(value) => values.push(value)
          None => return None
        }
      }
      match self.shader().type_inner(compose.ty) {
        Vector(_) => Some(Vector(values))
        _ => Some(Aggregate(values))
      }
    }
    @moonnaga.Splat(splat) =>
      match self.fold(splat.value) {
        Some(value) => {
          let values = []
          for _ in 0..<splat.size.to_int() {
            values.push(value)
          }
          Some(Vector(values))
        }
        None => None
      }
    @moonnaga.Unary(unary) =>
      match (unary.op, self.fold(unary.expr)) {
        (@moonnaga.Negate, Some(Int(value))) => Some(Int(-value))
        (@moonnaga.Negate, Some(Float(value))) => Some(Float(-value))
        (@moonnaga.LogicalNot, Some(Bool(value))) => Some(Bool(!value))
        _ => None
      }
    @moonnaga.Binary(binary) =>
      match (self.fold(binary.left), self.fold(binary.right)) {
        (Some(Int(left)), Some(Int(right))) =>
          fold_int_binary(binary.op, left, right)
        (Some(Float(left)), Some(Float(right))) =>
          fold_float_binary(binary.op, left, right)
        (Some(Int(left)), Some(Float(right))) =>
          fold_float_binary(binary.op, left.to_double(), right)
        (Some(Float(left)), Some(Int(right))) =>
          fold_float_binary(binary.op, left, right.to_double())
        (Some(Bool(left)), Some(Bool(right))) =>
          match binary.op {
            @moonnaga.BinaryOperator::LogicalAnd => Some(Bool(left && right))
            @moonnaga.BinaryOperator::LogicalOr => Some(Bool(left || right))
            @moonnaga.BinaryOperator::Equal => Some(Bool(left == right))
            @moonnaga.BinaryOperator::NotEqual => Some(Bool(left != right))
            _ => None
          }
        _ => None
      }
    @moonnaga.AccessIndex(access) =>
      match self.fold(access.base) {
        Some(Vector(values)) =>
          if access.index >= 0 && access.index.to_int() < values.length() {
            Some(values[access.index.to_int()])
          } else {
            None
          }
        Some(Aggregate(values)) =>
          if access.index >= 0 && access.index.to_int() < values.length() {
            Some(values[access.index.to_int()])
          } else {
            None
          }
        _ => None
      }
    @moonnaga.As(convert) =>
      match self.fold(convert.expr) {
        Some(Int(value)) =>
          match convert.kind {
            @moonnaga.Float => Some(Float(value.to_double()))
            @moonnaga.Uint => Some(Int(value))
            _ => Some(Int(value))
          }
        Some(Float(value)) =>
          match convert.kind {
            @moonnaga.Sint => Some(Int(value.to_int64()))
            @moonnaga.Uint => Some(Int(value.to_int64()))
            _ => Some(Float(value))
          }
        _ => None
      }
    _ => None
  }
}

///|
fn Builder::fold_constant(
  self : Builder,
  constant : @moonnaga.Handle,
) -> ConstValue? {
  let entry = self.shader().constants.get(constant)
  match self.fold_expr(self.shader().const_expressions.get(entry.init)) {
    Some(value) => Some(value)
    None => None
  }
}

///|
/// The zero value of a type, which `const x: T;` style initialisers and
/// `@moonnaga.ZeroValue` both need.
fn Builder::zero_of(self : Builder, ty : @moonnaga.Handle) -> ConstValue {
  match self.shader().type_inner(ty) {
    Scalar(scalar) =>
      match scalar.kind {
        @moonnaga.Float | @moonnaga.AbstractFloat => Float(0.0)
        @moonnaga.Bool => Bool(false)
        _ => Int(0)
      }
    Vector(vector) => {
      let element = self.zero_of(self.types.scalar_type(vector.scalar))
      let values = []
      for _ in 0..<vector.size.to_int() {
        values.push(element)
      }
      Vector(values)
    }
    Matrix(matrix) => {
      let rows = self.types.vector_type(matrix.rows, matrix.scalar)
      let fill = self.zero_of(rows)
      let values = []
      for _ in 0..<matrix.columns.to_int() {
        values.push(fill)
      }
      Aggregate(values)
    }
    Array(array) =>
      match array.size {
        @moonnaga.Fixed(count) => {
          let element = self.zero_of(array.base)
          let values = []
          for _ in 0..<count {
            values.push(element)
          }
          Aggregate(values)
        }
        _ => Aggregate([])
      }
    Struct(structure) => {
      let values = []
      for field in structure.members {
        values.push(self.zero_of(field.ty))
      }
      Aggregate(values)
    }
    _ => Int(0)
  }
}

///|
fn fold_int_binary(
  op : @moonnaga.BinaryOperator,
  left : Int64,
  right : Int64,
) -> ConstValue? {
  match op {
    @moonnaga.BinaryOperator::Add => Some(Int(left + right))
    @moonnaga.BinaryOperator::Subtract => Some(Int(left - right))
    @moonnaga.BinaryOperator::Multiply => Some(Int(left * right))
    @moonnaga.BinaryOperator::Divide =>
      if right == 0 {
        None
      } else {
        Some(Int(left / right))
      }
    @moonnaga.BinaryOperator::Modulo =>
      if right == 0 {
        None
      } else {
        Some(Int(left % right))
      }
    @moonnaga.BinaryOperator::Equal => Some(Bool(left == right))
    @moonnaga.BinaryOperator::NotEqual => Some(Bool(left != right))
    @moonnaga.BinaryOperator::Less => Some(Bool(left < right))
    @moonnaga.BinaryOperator::LessEqual => Some(Bool(left <= right))
    @moonnaga.BinaryOperator::Greater => Some(Bool(left > right))
    @moonnaga.BinaryOperator::GreaterEqual => Some(Bool(left >= right))
    @moonnaga.BinaryOperator::ShiftLeft => Some(Int(left << right.to_int()))
    @moonnaga.BinaryOperator::ShiftRight => Some(Int(left >> right.to_int()))
    _ => None
  }
}

///|
fn fold_float_binary(
  op : @moonnaga.BinaryOperator,
  left : Double,
  right : Double,
) -> ConstValue? {
  match op {
    @moonnaga.BinaryOperator::Add => Some(Float(left + right))
    @moonnaga.BinaryOperator::Subtract => Some(Float(left - right))
    @moonnaga.BinaryOperator::Multiply => Some(Float(left * right))
    @moonnaga.BinaryOperator::Divide => Some(Float(left / right))
    @moonnaga.BinaryOperator::Modulo => Some(Float(left % right))
    @moonnaga.BinaryOperator::Equal => Some(Bool(left == right))
    @moonnaga.BinaryOperator::NotEqual => Some(Bool(left != right))
    @moonnaga.BinaryOperator::Less => Some(Bool(left < right))
    @moonnaga.BinaryOperator::LessEqual => Some(Bool(left <= right))
    @moonnaga.BinaryOperator::Greater => Some(Bool(left > right))
    @moonnaga.BinaryOperator::GreaterEqual => Some(Bool(left >= right))
    _ => None
  }
}

///|
/// The value of a `const_assert`, which must hold; a false one is a compile
/// error with no runtime meaning.
fn Builder::check_const_assert(
  self : Builder,
  expr : Expr,
  span : @moonnaga.Span,
) -> Unit raise Failed {
  let handle = self.lower_value(expr)
  match self.fold(handle) {
    Some(Bool(true)) => ()
    Some(Bool(false)) => fail("`const_assert` fails", span)
    _ => fail("`const_assert` needs a constant", span)
  }
}
