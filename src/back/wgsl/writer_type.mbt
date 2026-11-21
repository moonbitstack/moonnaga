// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The WGSL spelling of a type. A named type writes as its name; an anonymous
/// one, such as `vec4<f32>`, is built from its parts.
fn Writer::type_text(self : Writer, handle : @moonnaga.Handle) -> String {
  let ty = self.shader.types.get(handle)
  match ty.name {
    Some(_) =>
      match self.type_names.get(handle.to_int()) {
        Some(name) => name
        None => self.inner_text(ty.inner)
      }
    None => self.inner_text(ty.inner)
  }
}

///|
fn Writer::inner_text(self : Writer, inner : @moonnaga.TypeInner) -> String {
  match inner {
    @moonnaga.Scalar(scalar) => @moonnaga.scalar_name(scalar)
    @moonnaga.Vector(vector) =>
      "vec" +
      vector.size.to_int().to_string() +
      "<" +
      @moonnaga.scalar_name(vector.scalar) +
      ">"
    @moonnaga.Matrix(matrix) =>
      "mat" +
      matrix.columns.to_int().to_string() +
      "x" +
      matrix.rows.to_int().to_string() +
      "<" +
      @moonnaga.scalar_name(matrix.scalar) +
      ">"
    @moonnaga.Atomic(scalar) =>
      "atomic_op<" + @moonnaga.scalar_name(scalar) + ">"
    @moonnaga.Pointer(pointer) =>
      "ptr<" +
      space_text(pointer.space) +
      ", " +
      self.type_text(pointer.base) +
      ">"
    @moonnaga.ValuePointer(pointer) =>
      match pointer.size {
        Some(size) =>
          "ptr<" +
          space_text(pointer.space) +
          ", vec" +
          size.to_int().to_string() +
          "<" +
          @moonnaga.scalar_name(pointer.scalar) +
          ">>"
        None =>
          "ptr<" +
          space_text(pointer.space) +
          ", " +
          @moonnaga.scalar_name(pointer.scalar) +
          ">"
      }
    @moonnaga.Array(array) =>
      match array.size {
        @moonnaga.Fixed(count) =>
          "array<" + self.type_text(array.base) + ", " + count.to_string() + ">"
        _ => "array<" + self.type_text(array.base) + ">"
      }
    @moonnaga.Struct(_) => "struct"
    @moonnaga.Image(image) => image_text(image)
    @moonnaga.Sampler(sampler) =>
      if sampler.comparison {
        "sampler_comparison"
      } else {
        "sampler"
      }
    @moonnaga.AccelerationStructure(_) => "acceleration_structure"
    @moonnaga.RayQuery(_) => "ray_query"
    @moonnaga.BindingArray(array) =>
      match array.size {
        @moonnaga.Fixed(count) =>
          "binding_array<" +
          self.type_text(array.base) +
          ", " +
          count.to_string() +
          ">"
        _ => "binding_array<" + self.type_text(array.base) + ">"
      }
  }
}

///|
fn space_text(space : @moonnaga.AddressSpace) -> String {
  match space {
    @moonnaga.Function => "function"
    @moonnaga.Private => "private"
    @moonnaga.WorkGroup => "workgroup"
    @moonnaga.Uniform => "uniform"
    @moonnaga.Storage(@moonnaga.Read) => "storage, read"
    @moonnaga.Storage(@moonnaga.Write) => "storage, write"
    @moonnaga.Storage(@moonnaga.ReadWrite) => "storage, read_write"
    @moonnaga.PushConstant => "push_constant"
    @moonnaga.Handle => "handle"
  }
}

///|
fn image_text(image : @moonnaga.ImageType) -> String {
  let array_tail = if image.arrayed { "_array" } else { "" }
  match image.class {
    @moonnaga.Sampling =>
      match image.dim {
        @moonnaga.D1 => "texture_1d<f32>"
        @moonnaga.D2 => "texture_2d" + array_tail + "<f32>"
        @moonnaga.D3 => "texture_3d<f32>"
        @moonnaga.Cube => "texture_cube" + array_tail + "<f32>"
      }
    @moonnaga.Depth =>
      match image.dim {
        @moonnaga.D2 => "texture_depth_2d" + array_tail
        @moonnaga.Cube => "texture_depth_cube" + array_tail
        _ => "texture_depth_2d"
      }
    @moonnaga.Storage(access, format) => {
      let dim = match image.dim {
        @moonnaga.D1 => "1d"
        @moonnaga.D2 => "2d"
        @moonnaga.D3 => "3d"
        @moonnaga.Cube => "2d"
      }
      let access = match access {
        @moonnaga.Read => "read"
        @moonnaga.Write => "write"
        @moonnaga.ReadWrite => "read_write"
      }
      "texture_storage_" + dim + array_tail + "<" + format + ", " + access + ">"
    }
  }
}

///|
/// A floating-point literal as WGSL writes it. The text always carries a decimal
/// point or an exponent, because `1f` is not a literal the grammar takes.
pub fn float_literal(value : Double, suffix : String) -> String {
  let text = value.to_string()
  let has_marker = text.contains(".") ||
    text.contains("e") ||
    text.contains("E") ||
    text.contains("N") ||
    text.contains("n")
  let body = if has_marker { text } else { text + ".0" }
  body + suffix
}

///|
fn Writer::literal_text(_self : Writer, literal : @moonnaga.Literal) -> String {
  match literal {
    @moonnaga.AbstractInt(value) => value.to_string()
    @moonnaga.AbstractFloat(value) => float_literal(value, "")
    @moonnaga.I32(value) => value.to_string() + "i"
    @moonnaga.U32(value) => value.to_string() + "u"
    @moonnaga.I64(value) => value.to_string() + "i"
    @moonnaga.U64(value) => value.to_string() + "u"
    @moonnaga.F32(value) => shortest_f32_text(value) + "f"
    @moonnaga.F64(value) => float_literal(value, "f")
    @moonnaga.Bool(value) => if value { "true" } else { "false" }
  }
}

///|
/// The shortest decimal text that reads back as the same 32-bit float.
///
/// A `f32` widened to a double prints with digits the source never wrote, so the
/// writer tries one significant digit at a time until the round trip closes;
/// that is what makes `1.2f` come back as `1.2f` rather than as
/// `1.2000000476837158f`.
fn shortest_f32_text(value : Float) -> String {
  let widened = value.to_double()
  let mut digits = 1
  while digits <= 9 {
    let rounded = round_significant(widened, digits)
    let text = rounded.to_string()
    if Float::from_double(rounded) == value {
      return text
    }
    digits = digits + 1
  }
  widened.to_string()
}

///|
fn round_significant(value : Double, digits : Int32) -> Double {
  if value == 0.0 {
    return 0.0
  }
  let mut magnitude = 0
  let mut magnitude_value = if value < 0.0 { -value } else { value }
  while magnitude_value >= 10.0 {
    magnitude_value = magnitude_value / 10.0
    magnitude = magnitude + 1
  }
  while magnitude_value < 1.0 {
    magnitude_value = magnitude_value * 10.0
    magnitude = magnitude - 1
  }
  let power = digits - 1 - magnitude
  let scale = power_of_ten(power)
  (value * scale).round() / scale
}

///|
fn power_of_ten(power : Int32) -> Double {
  let mut result = 1.0
  if power >= 0 {
    for _ in 0..<power {
      result = result * 10.0
    }
  } else {
    for _ in 0..<-power {
      result = result / 10.0
    }
  }
  result
}
