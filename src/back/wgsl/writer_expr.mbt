// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The writer's view of a function, which is what gives an expression its type.
pub(all) struct Frame {
  function : @moonnaga.Function
}

///|
fn Writer::frame_type(
  _self : Writer,
  frame : Frame,
  handle : @moonnaga.Handle,
) -> @moonnaga.Handle {
  let index = handle.to_int()
  if index >= 0 && index < frame.function.expr_types.length() {
    frame.function.expr_types[index]
  } else {
    { index: 0, }
  }
}

///|
fn Writer::expr_text(
  self : Writer,
  frame : Frame,
  handle : @moonnaga.Handle,
) -> String {
  match self.expr_names.get(handle.to_int()) {
    Some(name) => return name
    None => ()
  }
  match frame.function.expressions.get(handle) {
    @moonnaga.Literal(literal) => self.literal_text(literal)
    @moonnaga.Constant(constant) => self.const_name(constant)
    @moonnaga.Override(over) => self.shader.overrides.get(over).name
    @moonnaga.ZeroValue(ty) => self.type_text(ty) + "()"
    @moonnaga.Compose(compose) => {
      let parts = []
      for component in compose.components {
        parts.push(self.expr_text(frame, component))
      }
      self.type_text(compose.ty) + "(" + join_with(parts, ", ") + ")"
    }
    @moonnaga.Access(access) =>
      self.place_text(frame, access.base) +
      "[" +
      self.expr_text(frame, access.index) +
      "]"
    @moonnaga.AccessIndex(access) => {
      let base = self.place_text(frame, access.base)
      let container = self.frame_type(frame, access.base)
      match self.shader.type_inner(container) {
        @moonnaga.Struct(structure) =>
          if access.index >= 0 &&
            access.index.to_int() < structure.members.length() {
            base + "." + structure.members[access.index.to_int()].name
          } else {
            base + "[" + access.index.to_string() + "]"
          }
        @moonnaga.Vector(_) => base + "." + component_name(access.index)
        _ => base + "[" + access.index.to_string() + "]"
      }
    }
    @moonnaga.Splat(splat) => {
      let ty = self.frame_type(frame, handle)
      self.type_text(ty) + "(" + self.expr_text(frame, splat.value) + ")"
    }
    @moonnaga.Swizzle(swizzle) => {
      let parts = []
      for component in swizzle.pattern {
        parts.push(
          match component {
            @moonnaga.X => "x"
            @moonnaga.Y => "y"
            @moonnaga.Z => "z"
            @moonnaga.W => "w"
          },
        )
      }
      self.expr_text(frame, swizzle.vector) + "." + join_with(parts, "")
    }
    @moonnaga.FunctionArgument(index) => {
      let index = index.to_int()
      if index >= 0 && index < self.argument_names.length() {
        self.argument_names[index]
      } else {
        "arg" + index.to_string()
      }
    }
    @moonnaga.GlobalVariable(global) => self.global_name(global)
    @moonnaga.LocalVariable(slot) => self.local_name(slot)
    @moonnaga.Load(pointer) => self.place_text(frame, pointer)
    @moonnaga.ImageSample(sample) => self.image_sample_text(frame, sample)
    @moonnaga.ImageLoad(load) => self.image_load_text(frame, load)
    @moonnaga.ImageQuery(query) => {
      let name = match query.query {
        @moonnaga.Size => "textureDimensions"
        @moonnaga.NumLevels => "textureNumLevels"
        @moonnaga.NumLayers => "textureNumLayers"
        @moonnaga.NumSamples => "textureNumSamples"
      }
      name + "(" + self.expr_text(frame, query.image) + ")"
    }
    @moonnaga.Unary(unary) => {
      let operand = self.expr_text(frame, unary.expr)
      match unary.op {
        @moonnaga.Negate => "(-" + operand + ")"
        @moonnaga.LogicalNot => "(!" + operand + ")"
        @moonnaga.BitwiseNot => "(~" + operand + ")"
      }
    }
    @moonnaga.Binary(binary) =>
      "(" +
      self.expr_text(frame, binary.left) +
      " " +
      binary_text(binary.op) +
      " " +
      self.expr_text(frame, binary.right) +
      ")"
    @moonnaga.Select(select) =>
      "select(" +
      self.expr_text(frame, select.accept) +
      ", " +
      self.expr_text(frame, select.reject) +
      ", " +
      self.expr_text(frame, select.condition) +
      ")"
    @moonnaga.Derivative(derivative) => {
      let name = match (derivative.axis, derivative.ctrl) {
        (@moonnaga.X, @moonnaga.Coarse) => "dpdxCoarse"
        (@moonnaga.Y, @moonnaga.Coarse) => "dpdyCoarse"
        (@moonnaga.X, @moonnaga.Fine) => "dpdxFine"
        (@moonnaga.Y, @moonnaga.Fine) => "dpdyFine"
        (@moonnaga.X, _) => "dpdx"
        (@moonnaga.Y, _) => "dpdy"
        (@moonnaga.Width, _) => "fwidth"
      }
      name + "(" + self.expr_text(frame, derivative.expr) + ")"
    }
    @moonnaga.Relational(relational) => {
      let name = match relational.fun {
        @moonnaga.All => "all"
        @moonnaga.Any => "any"
        @moonnaga.IsNan => "isNan"
        @moonnaga.IsInf => "isInf"
      }
      name + "(" + self.expr_text(frame, relational.argument) + ")"
    }
    @moonnaga.Math(math) => self.math_text(frame, math)
    @moonnaga.As(convert) => {
      let target = self.frame_type(frame, handle)
      self.type_text(target) + "(" + self.expr_text(frame, convert.expr) + ")"
    }
    @moonnaga.CallResult(function) => self.function_name(function) + "()"
    @moonnaga.AtomicResult(_) => "_atomic"
    @moonnaga.WorkGroupUniformLoadResult(pointer) =>
      "workgroupUniformLoad(" + self.place_text(frame, pointer) + ")"
    @moonnaga.ArrayLength(pointer) =>
      "arrayLength(&" + self.place_text(frame, pointer) + ")"
  }
}

///|
/// An expression written where a place is wanted: the left side of a store, the
/// operand of a load, the base of a member access.
fn Writer::place_text(
  self : Writer,
  frame : Frame,
  handle : @moonnaga.Handle,
) -> String {
  match self.expr_names.get(handle.to_int()) {
    Some(name) => return name
    None => ()
  }
  match frame.function.expressions.get(handle) {
    @moonnaga.LocalVariable(slot) => self.local_name(slot)
    @moonnaga.GlobalVariable(global) => self.global_name(global)
    @moonnaga.FunctionArgument(index) => {
      let index = index.to_int()
      if index >= 0 && index < self.argument_names.length() {
        self.argument_names[index]
      } else {
        "arg" + index.to_string()
      }
    }
    @moonnaga.AccessIndex(access) => {
      let base = self.place_text(frame, access.base)
      let container = self.frame_type(frame, access.base)
      match self.shader.type_inner(container) {
        @moonnaga.Struct(structure) =>
          if access.index >= 0 &&
            access.index.to_int() < structure.members.length() {
            base + "." + structure.members[access.index.to_int()].name
          } else {
            base + "[" + access.index.to_string() + "]"
          }
        _ => base + "[" + access.index.to_string() + "]"
      }
    }
    @moonnaga.Access(access) =>
      self.place_text(frame, access.base) +
      "[" +
      self.expr_text(frame, access.index) +
      "]"
    @moonnaga.Load(pointer) => self.place_text(frame, pointer)
    @moonnaga.Swizzle(_swizzle) => self.expr_text(frame, handle)
    _ => self.expr_text(frame, handle)
  }
}

///|
fn Writer::const_name(self : Writer, handle : @moonnaga.Handle) -> String {
  match self.const_names.get(handle.to_int()) {
    Some(name) => name
    None => "const" + handle.to_int().to_string()
  }
}

///|
fn Writer::global_name(self : Writer, handle : @moonnaga.Handle) -> String {
  match self.global_names.get(handle.to_int()) {
    Some(name) => name
    None => "global" + handle.to_int().to_string()
  }
}

///|
fn Writer::function_name(self : Writer, handle : @moonnaga.Handle) -> String {
  match self.function_names.get(handle.to_int()) {
    Some(name) => name
    None => "func" + handle.to_int().to_string()
  }
}

///|
fn Writer::local_name(self : Writer, handle : @moonnaga.Handle) -> String {
  match self.local_names.get(handle.to_int()) {
    Some(name) => name
    None => "slot" + handle.to_int().to_string()
  }
}

///|
fn binary_text(op : @moonnaga.BinaryOperator) -> String {
  match op {
    @moonnaga.Add => "+"
    @moonnaga.Subtract => "-"
    @moonnaga.Multiply => "*"
    @moonnaga.Divide => "/"
    @moonnaga.Modulo => "%"
    @moonnaga.Equal => "=="
    @moonnaga.NotEqual => "!="
    @moonnaga.Less => "<"
    @moonnaga.LessEqual => "<="
    @moonnaga.Greater => ">"
    @moonnaga.GreaterEqual => ">="
    @moonnaga.And => "&"
    @moonnaga.ExclusiveOr => "^"
    @moonnaga.InclusiveOr => "|"
    @moonnaga.LogicalAnd => "&&"
    @moonnaga.LogicalOr => "||"
    @moonnaga.ShiftLeft => "<<"
    @moonnaga.ShiftRight => ">>"
  }
}

///|
fn math_name(fun : @moonnaga.MathFunction) -> String {
  match fun {
    @moonnaga.Abs => "abs"
    @moonnaga.Min => "min"
    @moonnaga.Max => "max"
    @moonnaga.Clamp => "clamp"
    @moonnaga.Saturate => "saturate"
    @moonnaga.Cos => "cos"
    @moonnaga.Cosh => "cosh"
    @moonnaga.Sin => "sin"
    @moonnaga.Sinh => "sinh"
    @moonnaga.Tan => "tan"
    @moonnaga.Tanh => "tanh"
    @moonnaga.Acos => "acos"
    @moonnaga.Asin => "asin"
    @moonnaga.Atan => "atan"
    @moonnaga.Atan2 => "atan2"
    @moonnaga.Asinh => "asinh"
    @moonnaga.Acosh => "acosh"
    @moonnaga.Atanh => "atanh"
    @moonnaga.Radians => "radians"
    @moonnaga.Degrees => "degrees"
    @moonnaga.Ceil => "ceil"
    @moonnaga.Floor => "floor"
    @moonnaga.Round => "round"
    @moonnaga.Fract => "fract"
    @moonnaga.Trunc => "trunc"
    @moonnaga.Modf => "modf"
    @moonnaga.Frexp => "frexp"
    @moonnaga.Ldexp => "ldexp"
    @moonnaga.Exp => "exp"
    @moonnaga.Exp2 => "exp2"
    @moonnaga.Log => "log"
    @moonnaga.Log2 => "log2"
    @moonnaga.Pow => "pow"
    @moonnaga.Dot => "dot"
    @moonnaga.Dot4I8Packed => "dot4I8Packed"
    @moonnaga.Dot4U8Packed => "dot4U8Packed"
    @moonnaga.Outer => "outer"
    @moonnaga.Cross => "cross"
    @moonnaga.Distance => "distance"
    @moonnaga.Length => "length"
    @moonnaga.Normalize => "normalize"
    @moonnaga.FaceForward => "faceForward"
    @moonnaga.Reflect => "reflect"
    @moonnaga.Refract => "refract"
    @moonnaga.Sign => "sign"
    @moonnaga.Fma => "fma"
    @moonnaga.Mix => "mix"
    @moonnaga.Step => "step"
    @moonnaga.SmoothStep => "smoothstep"
    @moonnaga.Sqrt => "sqrt"
    @moonnaga.InverseSqrt => "inverseSqrt"
    @moonnaga.Inverse => "inverse"
    @moonnaga.Transpose => "transpose"
    @moonnaga.Determinant => "determinant"
    @moonnaga.QuantizeToF16 => "quantizeToF16"
    @moonnaga.CountTrailingZeros => "countTrailingZeros"
    @moonnaga.CountLeadingZeros => "countLeadingZeros"
    @moonnaga.CountOneBits => "countOneBits"
    @moonnaga.ReverseBits => "reverseBits"
    @moonnaga.ExtractBits => "extractBits"
    @moonnaga.InsertBits => "insertBits"
    @moonnaga.FirstTrailingBit => "firstTrailingBit"
    @moonnaga.FirstLeadingBit => "firstLeadingBit"
    @moonnaga.Pack4x8snorm => "pack4x8snorm"
    @moonnaga.Pack4x8unorm => "pack4x8unorm"
    @moonnaga.Pack2x16snorm => "pack2x16snorm"
    @moonnaga.Pack2x16unorm => "pack2x16unorm"
    @moonnaga.Pack2x16float => "pack2x16float"
    @moonnaga.Pack4xI8 => "pack4xI8"
    @moonnaga.Pack4xU8 => "pack4xU8"
    @moonnaga.Pack4xI8Clamp => "pack4xI8Clamp"
    @moonnaga.Pack4xU8Clamp => "pack4xU8Clamp"
    @moonnaga.Unpack4x8snorm => "unpack4x8snorm"
    @moonnaga.Unpack4x8unorm => "unpack4x8unorm"
    @moonnaga.Unpack2x16snorm => "unpack2x16snorm"
    @moonnaga.Unpack2x16unorm => "unpack2x16unorm"
    @moonnaga.Unpack2x16float => "unpack2x16float"
    @moonnaga.Unpack4xI8 => "unpack4xI8"
    @moonnaga.Unpack4xU8 => "unpack4xU8"
  }
}

///|
fn Writer::math_text(
  self : Writer,
  frame : Frame,
  math : @moonnaga.MathExpr,
) -> String {
  let parts = [self.expr_text(frame, math.arg)]
  match math.arg1 {
    Some(handle) => parts.push(self.expr_text(frame, handle))
    None => ()
  }
  match math.arg2 {
    Some(handle) => parts.push(self.expr_text(frame, handle))
    None => ()
  }
  match math.arg3 {
    Some(handle) => parts.push(self.expr_text(frame, handle))
    None => ()
  }
  math_name(math.fun) + "(" + join_with(parts, ", ") + ")"
}

///|
fn Writer::image_sample_text(
  self : Writer,
  frame : Frame,
  sample : @moonnaga.ImageSampleExpr,
) -> String {
  let parts = []
  match sample.depth_ref {
    Some(_) => {
      parts.push(self.expr_text(frame, sample.image))
      parts.push(self.expr_text(frame, sample.sampler))
      parts.push(self.expr_text(frame, sample.coordinate))
      match sample.depth_ref {
        Some(reference) => parts.push(self.expr_text(frame, reference))
        None => ()
      }
    }
    None => {
      match sample.gather {
        Some(_) => {
          let component = match sample.gather {
            Some(@moonnaga.X) => "0"
            Some(@moonnaga.Y) => "1"
            Some(@moonnaga.Z) => "2"
            Some(@moonnaga.W) => "3"
            None => "0"
          }
          parts.push(component)
        }
        None => ()
      }
      parts.push(self.expr_text(frame, sample.image))
      parts.push(self.expr_text(frame, sample.sampler))
      parts.push(self.expr_text(frame, sample.coordinate))
    }
  }
  match sample.array_index {
    Some(index) => parts.push(self.expr_text(frame, index))
    None => ()
  }
  match sample.level {
    @moonnaga.Exact(handle) => {
      // `textureSampleLevel` puts the level right after the coordinate.
      let mut position = if sample.depth_ref is Some(_) {
        4
      } else if sample.gather is Some(_) {
        4
      } else {
        3
      }
      if position > parts.length() {
        position = parts.length()
      }
      parts.insert(position, self.expr_text(frame, handle))
    }
    @moonnaga.Bias(handle) => parts.push(self.expr_text(frame, handle))
    @moonnaga.Gradient(dx, dy) => {
      parts.push(self.expr_text(frame, dx))
      parts.push(self.expr_text(frame, dy))
    }
    _ => ()
  }
  match sample.offset {
    Some(handle) => parts.push(self.expr_text(frame, handle))
    None => ()
  }
  let name = if sample.depth_ref is Some(_) {
    if sample.gather is Some(_) {
      "textureGatherCompare"
    } else if sample.level == @moonnaga.Auto {
      "textureSampleCompare"
    } else {
      "textureSampleCompareLevel"
    }
  } else if sample.gather is Some(_) {
    "textureGather"
  } else {
    match sample.level {
      @moonnaga.Auto => "textureSample"
      @moonnaga.Exact(_) => "textureSampleLevel"
      @moonnaga.Bias(_) => "textureSampleBias"
      @moonnaga.Gradient(_, _) => "textureSampleGrad"
      @moonnaga.Zero => "textureSampleLevel"
    }
  }
  name + "(" + join_with(parts, ", ") + ")"
}

///|
fn Writer::image_load_text(
  self : Writer,
  frame : Frame,
  load : @moonnaga.ImageLoadExpr,
) -> String {
  let parts = [
    self.expr_text(frame, load.image),
    self.expr_text(frame, load.coordinate),
  ]
  match load.array_index {
    Some(index) => parts.push(self.expr_text(frame, index))
    None => ()
  }
  match load.level {
    Some(level) => parts.push(self.expr_text(frame, level))
    None => ()
  }
  match load.sample {
    Some(sample) => parts.push(self.expr_text(frame, sample))
    None => ()
  }
  "textureLoad(" + join_with(parts, ", ") + ")"
}

///|
/// The text of an expression that lives at module scope, where there is no
/// function to give it a type: a constant initialiser.
fn Writer::module_const_text(
  self : Writer,
  handle : @moonnaga.Handle,
) -> String {
  match self.expr_names.get(handle.to_int()) {
    Some(name) => return name
    None => ()
  }
  let expr = self.shader.const_expressions.get(handle)
  match expr {
    @moonnaga.Literal(literal) => self.literal_text(literal)
    @moonnaga.Constant(constant) => self.const_name(constant)
    @moonnaga.Override(over) => self.shader.overrides.get(over).name
    @moonnaga.ZeroValue(ty) => self.type_text(ty) + "()"
    @moonnaga.Compose(compose) => {
      let parts = []
      for component in compose.components {
        parts.push(self.module_const_text(component))
      }
      self.type_text(compose.ty) + "(" + join_with(parts, ", ") + ")"
    }
    @moonnaga.Splat(splat) => {
      let ty = self.shader.const_expressions.get(handle)
      ignore(ty)
      let parts = [self.module_const_text(splat.value)]
      let size = splat.size.to_int()
      "vec" + size.to_string() + "(" + join_with(parts, ", ") + ")"
    }
    @moonnaga.Unary(unary) => {
      let operand = self.module_const_text(unary.expr)
      match unary.op {
        @moonnaga.Negate => "(-" + operand + ")"
        @moonnaga.LogicalNot => "(!" + operand + ")"
        @moonnaga.BitwiseNot => "(~" + operand + ")"
      }
    }
    @moonnaga.Binary(binary) =>
      "(" +
      self.module_const_text(binary.left) +
      " " +
      binary_text(binary.op) +
      " " +
      self.module_const_text(binary.right) +
      ")"
    @moonnaga.AccessIndex(access) => {
      let base = self.module_const_text(access.base)
      base + "[" + access.index.to_string() + "]"
    }
    @moonnaga.As(convert) => {
      let inner = self.module_const_text(convert.expr)
      inner
    }
    @moonnaga.Math(math) => {
      let parts = [self.module_const_text(math.arg)]
      match math.arg1 {
        Some(handle) => parts.push(self.module_const_text(handle))
        None => ()
      }
      match math.arg2 {
        Some(handle) => parts.push(self.module_const_text(handle))
        None => ()
      }
      math_name(math.fun) + "(" + join_with(parts, ", ") + ")"
    }
    _ => "0"
  }
}

///|
/// The swizzle letter of a vector component, which reads better than an index
/// and is what the language's own examples use.
fn component_name(index : Int32) -> String {
  match index {
    0 => "x"
    1 => "y"
    2 => "z"
    3 => "w"
    _ => index.to_string()
  }
}
