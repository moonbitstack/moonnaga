// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The type an expression of the function being written has.
fn Writer::expr_type(
  self : Writer,
  handle : @moonnaga.Handle,
) -> @moonnaga.Handle raise SpvError {
  let function = match self.current {
    Some(function) => function
    None => unsupported("an expression outside a function")
  }
  let index = handle.to_int()
  if index < 0 || index >= function.expr_types.length() {
    return unsupported("an expression with no type")
  }
  function.expr_types[index]
}

///|
/// Whether the expression names a place rather than a value.
fn Writer::is_pointer(self : Writer, handle : @moonnaga.Handle) -> Bool {
  match self.current {
    Some(function) => {
      let index = handle.to_int()
      if index >= 0 && index < function.expr_spaces.length() {
        match function.expr_spaces[index] {
          Some(_) => true
          None => false
        }
      } else {
        false
      }
    }
    None => false
  }
}

///|
fn Writer::expression(
  self : Writer,
  handle : @moonnaga.Handle,
) -> Word raise SpvError {
  match self.expr_ids.get(handle.to_int()) {
    Some(id) => return id
    None => ()
  }
  let function = match self.current {
    Some(function) => function
    None => unsupported("an expression outside a function")
  }
  let expr = function.expressions.get(handle)
  let ty = self.expr_type(handle)
  let id = match expr {
    @moonnaga.Literal(_) => {
      // A literal in a function body lives in the function's own arena, so it is
      // written as a constant here rather than looked up in the module's.
      let type_id = self.type_word(ty)
      match expr {
        @moonnaga.Literal(literal) =>
          match literal {
            @moonnaga.Bool(value) =>
              self.builder.emit_result(
                if value {
                  op_constant_true
                } else {
                  op_constant_false
                },
                type_id,
                [],
              )
            @moonnaga.I32(value) =>
              self.builder.emit_result(op_constant, type_id, [
                value.reinterpret_as_uint(),
              ])
            @moonnaga.U32(value) =>
              self.builder.emit_result(op_constant, type_id, [value])
            @moonnaga.F32(value) =>
              self.builder.emit_result(op_constant, type_id, [
                value.reinterpret_as_uint(),
              ])
            @moonnaga.F64(value) => {
              let bits = value.reinterpret_as_uint64()
              self.builder.emit_result(op_constant, type_id, [
                low_word(bits),
                high_word(bits),
              ])
            }
            @moonnaga.I64(value) =>
              self.builder.emit_result(op_constant, type_id, [
                low_word(value.reinterpret_as_uint64()),
                high_word(value.reinterpret_as_uint64()),
              ])
            @moonnaga.U64(value) =>
              self.builder.emit_result(op_constant, type_id, [
                low_word(value),
                high_word(value),
              ])
            @moonnaga.AbstractInt(value) =>
              self.builder.emit_result(op_constant, type_id, [
                low_word(value.reinterpret_as_uint64()),
              ])
            @moonnaga.AbstractFloat(value) => {
              let bits = value.reinterpret_as_uint64()
              self.builder.emit_result(op_constant, type_id, [
                low_word(bits),
                high_word(bits),
              ])
            }
          }
        _ => 0
      }
    }
    @moonnaga.Constant(constant) => {
      let entry = self.shader.constants.get(constant)
      self.const_word(entry.init, entry.ty)
    }
    @moonnaga.ZeroValue(zero_type) =>
      self.builder.emit_result(op_constant_null, self.type_word(zero_type), [])
    @moonnaga.Compose(compose) => {
      let components = []
      for component in compose.components {
        components.push(self.expression(component))
      }
      self.builder.emit_result(
        op_composite_construct,
        self.type_word(compose.ty),
        components,
      )
    }
    @moonnaga.Splat(splat) => {
      let value = self.expression(splat.value)
      let components = []
      for _ in 0..<splat.size.to_int() {
        components.push(value)
      }
      self.builder.emit_result(
        op_composite_construct,
        self.type_word(ty),
        components,
      )
    }
    @moonnaga.Swizzle(swizzle) => {
      let vector = self.expression(swizzle.vector)
      let components = []
      for component in swizzle.pattern {
        components.push(component.to_int().reinterpret_as_uint())
      }
      self.builder.emit_result(
        op_vector_shuffle,
        self.type_word(ty),
        [vector, vector] + components,
      )
    }
    @moonnaga.Access(access) =>
      self.access_chain(
        access.base,
        Some(self.expression(access.index)),
        access.index,
      )
    @moonnaga.AccessIndex(access) =>
      self.access_chain(access.base, None, @moonnaga.Handle::new(access.index))
    @moonnaga.Load(pointer) => {
      let pointer_id = self.expression(pointer)
      self.builder.emit_result(op_load, self.type_word(ty), [pointer_id])
    }
    @moonnaga.FunctionArgument(index) => {
      let id = self.argument_ids[index.to_int()]
      if self.interface_loads.is_empty() {
        id
      } else {
        // The argument arrives in a global variable; the value is a load of it.
        self.builder.emit_result(op_load, self.type_word(ty), [id])
      }
    }
    @moonnaga.GlobalVariable(global) => {
      let id = self.global_id(global)
      match self.wrapped.get(global.to_int()) {
        Some(_) => {
          // The variable is a struct around the real type, so the value is the
          // first member of it.
          let pointer = self.builder.emit_typed(op_type_pointer, [
            self.storage_class(self.global_space(global)),
            self.type_word(ty),
          ])
          let zero = self.uint_constant(0)
          self.builder.emit_result(op_access_chain, pointer, [id, zero])
        }
        None => id
      }
    }
    @moonnaga.LocalVariable(slot) =>
      self.local_ids.get(slot.to_int()).unwrap_or(0)
    @moonnaga.Binary(binary) => self.binary(binary, ty)
    @moonnaga.Unary(unary) => self.unary(unary, ty)
    @moonnaga.Select(select) => {
      let condition = self.expression(select.condition)
      let accept = self.expression(select.accept)
      let reject = self.expression(select.reject)
      self.builder.emit_result(op_select, self.type_word(ty), [
        condition, accept, reject,
      ])
    }
    @moonnaga.Math(math) => self.math_call(math, ty)
    @moonnaga.As(convert) => self.convert(convert, ty)
    @moonnaga.CallResult(function_handle) =>
      self.builder.emit_result(op_function_call, self.type_word(ty), [
        self.function_id(function_handle),
      ])
    @moonnaga.Relational(relational) => {
      let argument = self.expression(relational.argument)
      let opcode = match relational.fun {
        @moonnaga.All => op_all
        @moonnaga.Any => op_any
        _ => unsupported("`isNan` and `isInf` in SPIR-V")
      }
      self.builder.emit_result(opcode, self.type_word(ty), [argument])
    }
    @moonnaga.ImageQuery(query) => {
      let image = self.expression(query.image)
      let uv = self.uint_constant(0)
      self.builder.emit_result(op_image_query_size_lod, self.type_word(ty), [
        image, uv,
      ])
    }
    @moonnaga.ImageLoad(load) => {
      let image = self.expression(load.image)
      let coordinate = self.expression(load.coordinate)
      self.builder.emit_result(op_image_fetch, self.type_word(ty), [
        image, coordinate,
      ])
    }
    @moonnaga.ImageSample(sample) => {
      let image = self.expression(sample.image)
      let sampler = self.expression(sample.sampler)
      let sampled = self.builder.emit_result(
        op_sampled_image,
        self.type_word(self.sampled_image_type(ty)),
        [image, sampler],
      )
      let coordinate = self.expression(sample.coordinate)
      self.builder.emit_result(
        op_image_sample_implicit_lod,
        self.type_word(ty),
        [sampled, coordinate],
      )
    }
    @moonnaga.Derivative(_) => unsupported("a derivative in SPIR-V")
    @moonnaga.ArrayLength(_) => unsupported("`arrayLength` in SPIR-V")
    @moonnaga.AtomicResult(_) => unsupported("an atomic_op result in SPIR-V")
    @moonnaga.WorkGroupUniformLoadResult(_) =>
      unsupported("a workgroup uniform load in SPIR-V")
    @moonnaga.Override(_) => unsupported("a pipeline constant in SPIR-V")
  }
  self.expr_ids[handle.to_int()] = id
  id
}

///|
/// The sampled-image type of a texture, which is what a sampler and an image pair
/// up into.
fn Writer::sampled_image_type(
  self : Writer,
  texel : @moonnaga.Handle,
) -> @moonnaga.Handle raise SpvError {
  for index in 0..<self.shader.types.len() {
    let handle = @moonnaga.Handle::new(index)
    match self.shader.types.get(handle).inner {
      @moonnaga.Image(_) => return handle
      _ => ()
    }
  }
  ignore(texel)
  unsupported("a texture type the shader never declared")
}

///|
/// A chain of `OpAccessChain` for a pointer base, or `OpCompositeExtract` when
/// the base is a value.
fn Writer::access_chain(
  self : Writer,
  base : @moonnaga.Handle,
  dynamic_index : Word?,
  static_index : @moonnaga.Handle,
) -> Word raise SpvError {
  let base_id = self.expression(base)
  if self.is_pointer(base) {
    let index = match dynamic_index {
      Some(index) => index
      None => self.uint_constant(static_index.to_int().reinterpret_as_uint())
    }
    let self_type = self.expr_type(base)
    let element = self.index_type(self_type, static_index)
    let result_type = self.builder.emit_typed(op_type_pointer, [
      self.pointer_class(base),
      self.type_word(element),
    ])
    self.builder.emit_result(op_access_chain, result_type, [base_id, index])
  } else {
    let index = match dynamic_index {
      Some(_) => unsupported("a dynamic index into a value")
      None => static_index.to_int().reinterpret_as_uint()
    }
    self.builder.emit_result(
      op_composite_extract,
      self.type_word(self.index_type(self.expr_type(base), static_index)),
      [base_id, index],
    )
  }
}

///|
/// The type one element of an indexable type has.
fn Writer::index_type(
  self : Writer,
  container : @moonnaga.Handle,
  index : @moonnaga.Handle,
) -> @moonnaga.Handle raise SpvError {
  match self.shader.types.get(container).inner {
    @moonnaga.Array(array) => array.base
    @moonnaga.Vector(vector) =>
      self.vector_scalar_handle(container, vector.scalar)
    @moonnaga.Matrix(matrix) => self.vector_handle(matrix.rows, matrix.scalar)
    @moonnaga.Struct(structure) =>
      if index.to_int() >= 0 && index.to_int() < structure.members.length() {
        structure.members[index.to_int()].ty
      } else {
        unsupported("a struct field that does not exist")
      }
    _ => unsupported("an index into a type that cannot be indexed")
  }
}

///|
fn Writer::binary(
  self : Writer,
  binary : @moonnaga.BinaryExpr,
  ty : @moonnaga.Handle,
) -> Word raise SpvError {
  let left = self.expression(binary.left)
  let right = self.expression(binary.right)
  let left_type = self.expr_type(binary.left)
  let scalar = self.shader.scalar_of(left_type)
  let is_float = match scalar {
    Some(scalar) => scalar.is_float()
    None =>
      match self.shader.type_inner(left_type) {
        @moonnaga.Matrix(matrix) => matrix.scalar.is_float()
        _ => false
      }
  }
  let is_signed = match scalar {
    Some(scalar) => scalar.kind == @moonnaga.Sint
    None => false
  }
  let opcode = match binary.op {
    @moonnaga.Add => if is_float { op_f_add } else { op_i_add }
    @moonnaga.Subtract => if is_float { op_f_sub } else { op_i_sub }
    @moonnaga.Multiply =>
      match
        (
          self.shader.type_inner(left_type),
          self.shader.type_inner(self.expr_type(binary.right)),
        ) {
        (@moonnaga.Matrix(_), @moonnaga.Vector(_)) => op_matrix_times_vector
        (@moonnaga.Vector(_), @moonnaga.Matrix(_)) => op_vector_times_matrix
        (@moonnaga.Matrix(_), @moonnaga.Matrix(_)) => op_matrix_times_matrix
        (@moonnaga.Matrix(_), @moonnaga.Scalar(_)) => op_vector_times_scalar
        (@moonnaga.Scalar(_), @moonnaga.Matrix(_)) => op_vector_times_scalar
        (@moonnaga.Vector(_), @moonnaga.Scalar(_)) => op_vector_times_scalar
        (@moonnaga.Scalar(_), @moonnaga.Vector(_)) => op_vector_times_scalar
        _ => if is_float { op_f_mul } else { op_i_mul }
      }
    @moonnaga.Divide =>
      if is_float {
        op_f_div
      } else if is_signed {
        op_s_div
      } else {
        op_u_div
      }
    @moonnaga.Modulo =>
      if is_float {
        op_f_mod
      } else if is_signed {
        op_s_rem
      } else {
        op_u_mod
      }
    @moonnaga.Equal => if is_float { op_f_ord_equal } else { op_i_equal }
    @moonnaga.NotEqual =>
      if is_float {
        op_f_ord_not_equal
      } else {
        op_i_not_equal
      }
    @moonnaga.Less =>
      if is_float {
        op_f_ord_less_than
      } else if is_signed {
        op_s_less_than
      } else {
        op_u_less_than
      }
    @moonnaga.LessEqual =>
      if is_float {
        op_f_ord_less_than_equal
      } else if is_signed {
        op_s_less_than_equal
      } else {
        op_u_less_than_equal
      }
    @moonnaga.Greater =>
      if is_float {
        op_f_ord_greater_than
      } else if is_signed {
        op_s_greater_than
      } else {
        op_u_greater_than
      }
    @moonnaga.GreaterEqual =>
      if is_float {
        op_f_ord_greater_than_equal
      } else if is_signed {
        op_s_greater_than_equal
      } else {
        op_u_greater_than_equal
      }
    @moonnaga.LogicalAnd => op_logical_and
    @moonnaga.LogicalOr => op_logical_or
    @moonnaga.And => op_bitwise_and
    @moonnaga.InclusiveOr => op_bitwise_or
    @moonnaga.ExclusiveOr => op_bitwise_xor
    @moonnaga.ShiftLeft => op_shift_left_logical
    @moonnaga.ShiftRight =>
      if is_signed {
        op_shift_right_arithmetic
      } else {
        op_shift_right_logical
      }
  }
  self.builder.emit_result(opcode, self.type_word(ty), [left, right])
}

///|
fn Writer::unary(
  self : Writer,
  unary : @moonnaga.UnaryExpr,
  ty : @moonnaga.Handle,
) -> Word raise SpvError {
  let value = self.expression(unary.expr)
  let scalar = self.shader.scalar_of(self.expr_type(unary.expr))
  let is_float = match scalar {
    Some(scalar) => scalar.is_float()
    None => false
  }
  let opcode = match unary.op {
    @moonnaga.Negate => if is_float { op_f_negate } else { op_s_negate }
    @moonnaga.LogicalNot => op_logical_not
    @moonnaga.BitwiseNot => op_not
  }
  self.builder.emit_result(opcode, self.type_word(ty), [value])
}

///|
/// The extended instruction number of a math function in `GLSL.std.450`.
fn glsl_number(fun : @moonnaga.MathFunction) -> Word? {
  match fun {
    @moonnaga.Round => Some(1)
    @moonnaga.Trunc => Some(3)
    @moonnaga.Abs => Some(4)
    @moonnaga.Sign => Some(6)
    @moonnaga.Floor => Some(8)
    @moonnaga.Ceil => Some(9)
    @moonnaga.Fract => Some(10)
    @moonnaga.Radians => Some(11)
    @moonnaga.Degrees => Some(12)
    @moonnaga.Sin => Some(13)
    @moonnaga.Cos => Some(14)
    @moonnaga.Tan => Some(15)
    @moonnaga.Asin => Some(16)
    @moonnaga.Acos => Some(17)
    @moonnaga.Atan => Some(18)
    @moonnaga.Sinh => Some(19)
    @moonnaga.Cosh => Some(20)
    @moonnaga.Tanh => Some(21)
    @moonnaga.Asinh => Some(22)
    @moonnaga.Acosh => Some(23)
    @moonnaga.Atanh => Some(24)
    @moonnaga.Atan2 => Some(25)
    @moonnaga.Pow => Some(26)
    @moonnaga.Exp => Some(27)
    @moonnaga.Log => Some(28)
    @moonnaga.Exp2 => Some(29)
    @moonnaga.Log2 => Some(30)
    @moonnaga.Sqrt => Some(31)
    @moonnaga.InverseSqrt => Some(32)
    @moonnaga.Determinant => Some(33)
    @moonnaga.Inverse => Some(34)
    @moonnaga.Min => Some(37)
    @moonnaga.Max => Some(40)
    @moonnaga.Clamp => Some(43)
    @moonnaga.Mix => Some(46)
    @moonnaga.Step => Some(48)
    @moonnaga.SmoothStep => Some(49)
    @moonnaga.Fma => Some(50)
    @moonnaga.Ldexp => Some(53)
    @moonnaga.Length => Some(66)
    @moonnaga.Distance => Some(67)
    @moonnaga.Cross => Some(68)
    @moonnaga.Normalize => Some(69)
    @moonnaga.FaceForward => Some(70)
    @moonnaga.Reflect => Some(71)
    @moonnaga.Refract => Some(72)
    @moonnaga.Transpose => Some(84)
    _ => None
  }
}

///|
fn Writer::math_call(
  self : Writer,
  math : @moonnaga.MathExpr,
  ty : @moonnaga.Handle,
) -> Word raise SpvError {
  let number = match glsl_number(math.fun) {
    Some(number) => number
    None => unsupported("this math function in SPIR-V")
  }
  let arguments = [self.glsl_id, number, self.expression(math.arg)]
  match math.arg1 {
    Some(handle) => arguments.push(self.expression(handle))
    None => ()
  }
  match math.arg2 {
    Some(handle) => arguments.push(self.expression(handle))
    None => ()
  }
  match math.arg3 {
    Some(handle) => arguments.push(self.expression(handle))
    None => ()
  }
  self.builder.emit_result(op_ext_inst, self.type_word(ty), arguments)
}

///|
fn Writer::convert(
  self : Writer,
  convert : @moonnaga.AsExpr,
  ty : @moonnaga.Handle,
) -> Word raise SpvError {
  let source = self.expr_type(convert.expr)
  let source_scalar = self.shader.scalar_of(source)
  let target_scalar = self.shader.scalar_of(ty)
  let value = self.expression(convert.expr)
  let opcode = match (source_scalar, target_scalar) {
    (Some(from), Some(to)) =>
      if from.kind == to.kind && from.width == to.width {
        op_bitcast
      } else {
        match (from.kind, to.kind) {
          (@moonnaga.Sint, @moonnaga.Float)
          | (@moonnaga.Uint, @moonnaga.Float) =>
            if from.kind == @moonnaga.Sint {
              op_convert_s_to_f
            } else {
              op_convert_u_to_f
            }
          (@moonnaga.Float, @moonnaga.Sint)
          | (@moonnaga.Float, @moonnaga.Uint) =>
            if to.kind == @moonnaga.Sint {
              op_convert_f_to_s
            } else {
              op_convert_f_to_u
            }
          _ => op_bitcast
        }
      }
    _ => op_bitcast
  }
  self.builder.emit_result(opcode, self.type_word(ty), [value])
}

///|
/// The storage class a pointer to this expression's data lives in. A `let` bound
/// to a pointer keeps the space of the place it points at; an access chain off a
/// local stays in the function space.
fn Writer::pointer_class(self : Writer, base : @moonnaga.Handle) -> Word {
  match self.current {
    Some(function) => {
      let index = base.to_int()
      if index >= 0 && index < function.expr_spaces.length() {
        match function.expr_spaces[index] {
          Some(space) => self.storage_class(space)
          None => class_function
        }
      } else {
        class_function
      }
    }
    None => class_function
  }
}

///|
/// The address space of a global variable.
fn Writer::global_space(
  self : Writer,
  handle : @moonnaga.Handle,
) -> @moonnaga.AddressSpace {
  self.shader.global_variables.get(handle).space
}
