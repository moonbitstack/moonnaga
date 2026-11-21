// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The arithmetic functions WGSL predeclares, as the intermediate representation
/// names them.
fn math_by_name(name : String) -> @moonnaga.MathFunction? {
  match name {
    "abs" => Some(@moonnaga.Abs)
    "min" => Some(@moonnaga.Min)
    "max" => Some(@moonnaga.Max)
    "clamp" => Some(@moonnaga.Clamp)
    "saturate" => Some(@moonnaga.Saturate)
    "cos" => Some(@moonnaga.Cos)
    "cosh" => Some(@moonnaga.Cosh)
    "sin" => Some(@moonnaga.Sin)
    "sinh" => Some(@moonnaga.Sinh)
    "tan" => Some(@moonnaga.Tan)
    "tanh" => Some(@moonnaga.Tanh)
    "acos" => Some(@moonnaga.Acos)
    "asin" => Some(@moonnaga.Asin)
    "atan" => Some(@moonnaga.Atan)
    "atan2" => Some(@moonnaga.Atan2)
    "acosh" => Some(@moonnaga.Acosh)
    "asinh" => Some(@moonnaga.Asinh)
    "atanh" => Some(@moonnaga.Atanh)
    "radians" => Some(@moonnaga.Radians)
    "degrees" => Some(@moonnaga.Degrees)
    "ceil" => Some(@moonnaga.Ceil)
    "floor" => Some(@moonnaga.Floor)
    "round" => Some(@moonnaga.Round)
    "fract" => Some(@moonnaga.Fract)
    "trunc" => Some(@moonnaga.Trunc)
    "ldexp" => Some(@moonnaga.Ldexp)
    "exp" => Some(@moonnaga.Exp)
    "exp2" => Some(@moonnaga.Exp2)
    "log" => Some(@moonnaga.Log)
    "log2" => Some(@moonnaga.Log2)
    "pow" => Some(@moonnaga.Pow)
    "dot" => Some(@moonnaga.Dot)
    "dot4I8Packed" => Some(@moonnaga.Dot4I8Packed)
    "dot4U8Packed" => Some(@moonnaga.Dot4U8Packed)
    "outer" => Some(@moonnaga.Outer)
    "cross" => Some(@moonnaga.Cross)
    "distance" => Some(@moonnaga.Distance)
    "length" => Some(@moonnaga.Length)
    "normalize" => Some(@moonnaga.Normalize)
    "faceForward" => Some(@moonnaga.FaceForward)
    "reflect" => Some(@moonnaga.Reflect)
    "refract" => Some(@moonnaga.Refract)
    "sign" => Some(@moonnaga.Sign)
    "fma" => Some(@moonnaga.Fma)
    "mix" => Some(@moonnaga.Mix)
    "step" => Some(@moonnaga.Step)
    "smoothstep" => Some(@moonnaga.SmoothStep)
    "sqrt" => Some(@moonnaga.Sqrt)
    "inverseSqrt" => Some(@moonnaga.InverseSqrt)
    "inverse" => Some(@moonnaga.Inverse)
    "transpose" => Some(@moonnaga.Transpose)
    "determinant" => Some(@moonnaga.Determinant)
    "quantizeToF16" => Some(@moonnaga.QuantizeToF16)
    "countTrailingZeros" => Some(@moonnaga.CountTrailingZeros)
    "countLeadingZeros" => Some(@moonnaga.CountLeadingZeros)
    "countOneBits" => Some(@moonnaga.CountOneBits)
    "reverseBits" => Some(@moonnaga.ReverseBits)
    "extractBits" => Some(@moonnaga.ExtractBits)
    "insertBits" => Some(@moonnaga.InsertBits)
    "firstTrailingBit" => Some(@moonnaga.FirstTrailingBit)
    "firstLeadingBit" => Some(@moonnaga.FirstLeadingBit)
    "pack4x8snorm" => Some(@moonnaga.Pack4x8snorm)
    "pack4x8unorm" => Some(@moonnaga.Pack4x8unorm)
    "pack2x16snorm" => Some(@moonnaga.Pack2x16snorm)
    "pack2x16unorm" => Some(@moonnaga.Pack2x16unorm)
    "pack2x16float" => Some(@moonnaga.Pack2x16float)
    "pack4xI8" => Some(@moonnaga.Pack4xI8)
    "pack4xU8" => Some(@moonnaga.Pack4xU8)
    "pack4xI8Clamp" => Some(@moonnaga.Pack4xI8Clamp)
    "pack4xU8Clamp" => Some(@moonnaga.Pack4xU8Clamp)
    "unpack4x8snorm" => Some(@moonnaga.Unpack4x8snorm)
    "unpack4x8unorm" => Some(@moonnaga.Unpack4x8unorm)
    "unpack2x16snorm" => Some(@moonnaga.Unpack2x16snorm)
    "unpack2x16unorm" => Some(@moonnaga.Unpack2x16unorm)
    "unpack2x16float" => Some(@moonnaga.Unpack2x16float)
    "unpack4xI8" => Some(@moonnaga.Unpack4xI8)
    "unpack4xU8" => Some(@moonnaga.Unpack4xU8)
    _ => None
  }
}

///|
/// How many arguments the function takes.
fn math_arity(fun : @moonnaga.MathFunction) -> Int32 {
  match fun {
    @moonnaga.Min
    | @moonnaga.Max
    | @moonnaga.Atan2
    | @moonnaga.Pow
    | @moonnaga.Step
    | @moonnaga.Dot
    | @moonnaga.Distance
    | @moonnaga.Outer
    | @moonnaga.Cross
    | @moonnaga.Reflect
    | @moonnaga.Ldexp
    | @moonnaga.Dot4I8Packed
    | @moonnaga.Dot4U8Packed => 2
    @moonnaga.Clamp
    | @moonnaga.Mix
    | @moonnaga.SmoothStep
    | @moonnaga.Fma
    | @moonnaga.FaceForward
    | @moonnaga.Refract
    | @moonnaga.ExtractBits => 3
    @moonnaga.InsertBits => 4
    _ => 1
  }
}

///|
/// Which argument carries the result's type. `step(edge, x)` is a `x`, and a
/// `smoothstep` is its third argument.
fn math_value_index(fun : @moonnaga.MathFunction) -> Int32 {
  match fun {
    @moonnaga.Step => 1
    @moonnaga.SmoothStep => 2
    _ => 0
  }
}

///|
/// The type a call to this function produces, given its arguments.
fn Builder::math_result(
  self : Builder,
  fun : @moonnaga.MathFunction,
  args : Array[@moonnaga.Handle],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let value = args[math_value_index(fun).to_int()]
  let value_ty = self.type_of(value)
  match fun {
    @moonnaga.Dot
    | @moonnaga.Length
    | @moonnaga.Distance
    | @moonnaga.Determinant =>
      match self.shader().scalar_of(value_ty) {
        Some(scalar) => self.types.scalar_type(scalar)
        None => fail("this function needs a vector or a matrix", span)
      }
    @moonnaga.Cross =>
      match self.shader().type_inner(value_ty) {
        Vector(vector) => self.types.vector_type(@moonnaga.Tri, vector.scalar)
        _ => fail("`cross` needs two vectors", span)
      }
    @moonnaga.Outer => {
      let left = self.shader().type_inner(self.type_of(args[0]))
      let right = self.shader().type_inner(self.type_of(args[1]))
      match (left, right) {
        (Vector(column), Vector(row)) =>
          self.types.matrix_type(column.size, row.size, column.scalar)
        _ => fail("`outer` needs two vectors", span)
      }
    }
    @moonnaga.Transpose =>
      match self.shader().type_inner(value_ty) {
        Matrix(matrix) =>
          self.types.matrix_type(matrix.rows, matrix.columns, matrix.scalar)
        _ => fail("`transpose` needs a matrix", span)
      }
    @moonnaga.Pack4x8snorm | @moonnaga.Pack4x8unorm =>
      self.types.scalar_type(@moonnaga.scalar_u32)
    @moonnaga.Pack2x16snorm
    | @moonnaga.Pack2x16unorm
    | @moonnaga.Pack2x16float => self.types.scalar_type(@moonnaga.scalar_u32)
    @moonnaga.Pack4xI8
    | @moonnaga.Pack4xU8
    | @moonnaga.Pack4xI8Clamp
    | @moonnaga.Pack4xU8Clamp => self.types.scalar_type(@moonnaga.scalar_u32)
    @moonnaga.Unpack4x8snorm
    | @moonnaga.Unpack4x8unorm
    | @moonnaga.Unpack2x16snorm
    | @moonnaga.Unpack2x16unorm
    | @moonnaga.Unpack2x16float =>
      self.types.vector_type(@moonnaga.Quad, @moonnaga.scalar_f32)
    @moonnaga.Unpack4xI8 | @moonnaga.Unpack4xU8 =>
      self.types.vector_type(@moonnaga.Quad, @moonnaga.scalar_i32)
    @moonnaga.Dot4I8Packed | @moonnaga.Dot4U8Packed =>
      self.types.scalar_type(@moonnaga.scalar_i32)
    _ => value_ty
  }
}

///|
fn Builder::math_call(
  self : Builder,
  fun : @moonnaga.MathFunction,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let arity = math_arity(fun)
  if args.length() != arity.to_int() {
    return fail("this function takes \{arity} arguments", span)
  }
  let lowered = []
  for arg in args {
    lowered.push(self.lower_value(arg))
  }
  let value_ty = self.type_of(lowered[math_value_index(fun).to_int()])
  // A scalar bound for a vector operation is a splat, as in `clamp(v, 0.0, 1.0)`.
  for index in 0..<lowered.length() {
    let ty = self.type_of(lowered[index])
    if ty != value_ty && index != math_value_index(fun).to_int() {
      match (self.shader().type_inner(ty), self.shader().type_inner(value_ty)) {
        (Scalar(scalar), Vector(vector)) =>
          if scalar.kind == vector.scalar.kind {
            let splat = self.emit(
              @moonnaga.Splat({ size: vector.size, value: lowered[index], }),
              Plain(value_ty),
            )
            lowered[index] = splat
          }
        _ => self.coerce(lowered[index], value_ty)
      }
    }
  }
  let result = self.math_result(fun, lowered, span)
  let arg0 = lowered[0]
  let arg1 = if lowered.length() > 1 { Some(lowered[1]) } else { None }
  let arg2 = if lowered.length() > 2 { Some(lowered[2]) } else { None }
  let arg3 = if lowered.length() > 3 { Some(lowered[3]) } else { None }
  self.emit(
    @moonnaga.Math({ fun, arg: arg0, arg1, arg2, arg3, }),
    Plain(result),
  )
}

///|
/// The calls that are statements rather than values, plus the ones whose result
/// type needs the arguments looked at in their own way.
fn Builder::call_builtin(
  self : Builder,
  name : String,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match name {
    "workgroupBarrier" => {
      self.emits.push(@moonnaga.ControlBarrier(@moonnaga.Workgroup))
      return self.unit_value()
    }
    "storageBarrier" => {
      self.emits.push(@moonnaga.MemoryBarrier(@moonnaga.Storage))
      return self.unit_value()
    }
    "textureBarrier" => {
      self.emits.push(@moonnaga.MemoryBarrier(@moonnaga.Texture))
      return self.unit_value()
    }
    "arrayLength" => {
      let pointer = self.lower_expr(args[0])
      let ty = self.types.scalar_type(@moonnaga.scalar_u32)
      return self.emit(@moonnaga.ArrayLength(pointer), Plain(ty))
    }
    "select" => {
      let accept = self.lower_value(args[0])
      let reject = self.lower_value(args[1])
      self.coerce(reject, self.type_of(accept))
      let condition = self.lower_value(args[2])
      return self.emit(
        @moonnaga.Select({ condition, accept, reject, }),
        Plain(self.type_of(accept)),
      )
    }
    "all" | "any" | "isNan" | "isInf" => {
      let value = self.lower_value(args[0])
      let fun = match name {
        "all" => @moonnaga.All
        "any" => @moonnaga.Any
        "isNan" => @moonnaga.IsNan
        _ => @moonnaga.IsInf
      }
      let ty = match self.shader().type_inner(self.type_of(value)) {
        Vector(vector) =>
          self.types.vector_type(vector.size, @moonnaga.boolean())
        _ => self.types.scalar_type(@moonnaga.boolean())
      }
      return self.emit(
        @moonnaga.Relational({ fun, argument: value, }),
        Plain(ty),
      )
    }
    "dpdx"
    | "dpdy"
    | "fwidth"
    | "dpdxCoarse"
    | "dpdyCoarse"
    | "dpdxFine"
    | "dpdyFine"
    | "fwidthCoarse"
    | "fwidthFine" => {
      let value = self.lower_value(args[0])
      let (axis, ctrl) = match name {
        "dpdx" => (@moonnaga.DerivativeAxis::X, @moonnaga.None)
        "dpdy" => (@moonnaga.DerivativeAxis::Y, @moonnaga.None)
        "fwidth" => (@moonnaga.DerivativeAxis::Width, @moonnaga.None)
        "dpdxCoarse" => (@moonnaga.DerivativeAxis::X, @moonnaga.Coarse)
        "dpdyCoarse" => (@moonnaga.DerivativeAxis::Y, @moonnaga.Coarse)
        "dpdxFine" => (@moonnaga.DerivativeAxis::X, @moonnaga.Fine)
        "fwidthCoarse" => (@moonnaga.DerivativeAxis::Width, @moonnaga.Coarse)
        "fwidthFine" => (@moonnaga.DerivativeAxis::Width, @moonnaga.Fine)
        _ => (@moonnaga.DerivativeAxis::Y, @moonnaga.Fine)
      }
      return self.emit(
        @moonnaga.Derivative({ axis, ctrl, expr: value, }),
        Plain(self.type_of(value)),
      )
    }
    "workgroupUniformLoad" => {
      let pointer = self.lower_expr(args[0])
      let ty = self.type_of(pointer)
      let result = self.emit(
        @moonnaga.WorkGroupUniformLoadResult(pointer),
        Plain(ty),
      )
      self.emits.push(@moonnaga.WorkGroupUniformLoad({ pointer, result, }))
      return result
    }
    _ =>
      match math_by_name(name) {
        Some(fun) => self.math_call(fun, args, span)
        None =>
          if name.has_prefix("texture") || name.has_prefix("atomic") {
            self.call_resource_builtin(name, args, span)
          } else {
            fail(
              "`\{name}` is not a function this shader or the language declares",
              span,
            )
          }
      }
  }
}

///|
/// A value with no meaning, used where a statement-shaped call still has to
/// produce an expression handle.
fn Builder::unit_value(self : Builder) -> @moonnaga.Handle {
  let ty = self.types.scalar_type(@moonnaga.boolean())
  self.emit(@moonnaga.ZeroValue(ty), Plain(ty))
}
