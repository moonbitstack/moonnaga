// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Resolves a written type to a handle, adding the type to the module the first
/// time it appears.
fn Builder::resolve_type(
  self : Builder,
  expr : TypeExpr,
) -> @moonnaga.Handle raise Failed {
  match expr {
    Pointer(pointer) => {
      let base = self.resolve_type(pointer.base)
      let space = match pointer.space {
        "function" => @moonnaga.Function
        "private" => @moonnaga.Private
        "workgroup" => @moonnaga.WorkGroup
        "uniform" => @moonnaga.Uniform
        "storage" => {
          let access = match pointer.access {
            Some("read_write") => @moonnaga.ReadWrite
            Some("write") => @moonnaga.Write
            _ => @moonnaga.Read
          }
          @moonnaga.Storage(access)
        }
        "push_constant" => @moonnaga.PushConstant
        other => fail("`\{other}` is not an address space", pointer.span)
      }
      self.types.pointer_type(base, space)
    }
    Named(name, args, span) => self.resolve_named(name, args, span)
  }
}

///|
fn Builder::resolve_named(
  self : Builder,
  name : String,
  args : Array[TemplateArg],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match name {
    "i32" => self.types.scalar_type(@moonnaga.scalar_i32)
    "u32" => self.types.scalar_type(@moonnaga.scalar_u32)
    "f32" => self.types.scalar_type(@moonnaga.scalar_f32)
    "f64" => self.types.scalar_type(@moonnaga.scalar_f64)
    "i64" => self.types.scalar_type(@moonnaga.scalar_i64)
    "u64" => self.types.scalar_type(@moonnaga.scalar_u64)
    "f16" => self.types.scalar_type(@moonnaga.float(2))
    "bool" => self.types.scalar_type(@moonnaga.boolean())
    "vec2f" | "vec3f" | "vec4f" =>
      self.types.vector_type(
        match name {
          "vec2f" => @moonnaga.Bi
          "vec3f" => @moonnaga.Tri
          _ => @moonnaga.Quad
        },
        @moonnaga.scalar_f32,
      )
    "vec2i" | "vec3i" | "vec4i" =>
      self.types.vector_type(
        match name {
          "vec2i" => @moonnaga.Bi
          "vec3i" => @moonnaga.Tri
          _ => @moonnaga.Quad
        },
        @moonnaga.scalar_i32,
      )
    "vec2u" | "vec3u" | "vec4u" =>
      self.types.vector_type(
        match name {
          "vec2u" => @moonnaga.Bi
          "vec3u" => @moonnaga.Tri
          _ => @moonnaga.Quad
        },
        @moonnaga.scalar_u32,
      )
    "mat2x2f" =>
      self.types.matrix_type(@moonnaga.Bi, @moonnaga.Bi, @moonnaga.scalar_f32)
    "mat3x3f" =>
      self.types.matrix_type(@moonnaga.Tri, @moonnaga.Tri, @moonnaga.scalar_f32)
    "mat4x4f" =>
      self.types.matrix_type(
        @moonnaga.Quad,
        @moonnaga.Quad,
        @moonnaga.scalar_f32,
      )
    "vec2" | "vec3" | "vec4" => {
      let size = match name {
        "vec2" => @moonnaga.Bi
        "vec3" => @moonnaga.Tri
        _ => @moonnaga.Quad
      }
      let scalar = self.scalar_argument(args, 0, span)
      self.types.vector_type(size, scalar)
    }
    "mat2x2"
    | "mat2x3"
    | "mat2x4"
    | "mat3x2"
    | "mat3x3"
    | "mat3x4"
    | "mat4x2"
    | "mat4x3"
    | "mat4x4" => {
      let letters = name.to_array()
      let columns = match
        @moonnaga.VectorSize::from_int(letters[3].to_int() - '0'.to_int()) {
        Some(size) => size
        None => fail("bad matrix name", span)
      }
      let rows = match
        @moonnaga.VectorSize::from_int(letters[5].to_int() - '0'.to_int()) {
        Some(size) => size
        None => fail("bad matrix name", span)
      }
      let scalar = self.scalar_argument(args, 0, span)
      self.types.matrix_type(columns, rows, scalar)
    }
    "array" => {
      if args.length() == 0 {
        return fail("an array needs an element type", span)
      }
      let base = self.resolve_type_arg(args[0], span)
      let size = if args.length() > 1 {
        match args[1] {
          Expr(expr) => @moonnaga.Fixed(self.const_int(expr))
          Type(_) => fail("an array length is an expression", span)
        }
      } else {
        @moonnaga.Dynamic
      }
      self.types.array_type(base, size)
    }
    "binding_array" => {
      if args.length() == 0 {
        return fail("a binding array needs an element type", span)
      }
      let base = self.resolve_type_arg(args[0], span)
      let size = if args.length() > 1 {
        match args[1] {
          Expr(expr) => @moonnaga.Fixed(self.const_int(expr))
          Type(_) => fail("a binding array length is an expression", span)
        }
      } else {
        @moonnaga.Dynamic
      }
      self.types.binding_array_type(base, size)
    }
    "atomic" => {
      let scalar = self.scalar_argument(args, 0, span)
      self.types.atomic_type(scalar)
    }
    "sampler" => self.types.sampler_type(false)
    "sampler_comparison" => self.types.sampler_type(true)
    "texture_external" =>
      self.types.image_type(@moonnaga.D2, false, @moonnaga.Sampling)
    "acceleration_structure" =>
      self.types.intern(
        "accel",
        @moonnaga.Type::new(
          None,
          AccelerationStructure({ vertex_return: false, }),
        ),
      )
    "ray_query" =>
      self.types.intern(
        "ray_query",
        @moonnaga.Type::new(None, RayQuery({ vertex_return: false, })),
      )
    _ => {
      // Texture types all read the same way: a dimension and an optional
      // format, with `depth` and `storage` changing what the texels mean.
      if name.has_prefix("texture_") {
        return self.resolve_texture(name, args, span)
      }
      match self.types.lookup(name) {
        Some(handle) => handle
        None => fail("`\{name}` is not a type", span)
      }
    }
  }
}

///|
fn Builder::resolve_type_arg(
  self : Builder,
  arg : TemplateArg,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match arg {
    Type(expr) => self.resolve_type(expr)
    Expr(_) => fail("expected a type", span)
  }
}

///|
/// The scalar a `vec` or `mat` is made of, or `f32` when the source left it out.
fn Builder::scalar_argument(
  self : Builder,
  args : Array[TemplateArg],
  index : Int32,
  span : @moonnaga.Span,
) -> @moonnaga.Scalar raise Failed {
  if args.length() <= index {
    return @moonnaga.scalar_f32
  }
  let handle = self.resolve_type_arg(args[index.to_int()], span)
  match self.shader().type_inner(handle) {
    Scalar(scalar) => scalar
    _ => fail("expected a scalar type", span)
  }
}

///|
fn Builder::resolve_texture(
  self : Builder,
  name : String,
  args : Array[TemplateArg],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match name {
    "texture_1d" =>
      self.types.image_type(@moonnaga.D1, false, @moonnaga.Sampling)
    "texture_2d" =>
      self.types.image_type(@moonnaga.D2, false, @moonnaga.Sampling)
    "texture_2d_array" =>
      self.types.image_type(@moonnaga.D2, true, @moonnaga.Sampling)
    "texture_3d" =>
      self.types.image_type(@moonnaga.D3, false, @moonnaga.Sampling)
    "texture_cube" =>
      self.types.image_type(@moonnaga.Cube, false, @moonnaga.Sampling)
    "texture_cube_array" =>
      self.types.image_type(@moonnaga.Cube, true, @moonnaga.Sampling)
    "texture_multisampled_2d" =>
      self.types.image_type(@moonnaga.D2, false, @moonnaga.Sampling)
    "texture_depth_2d" =>
      self.types.image_type(@moonnaga.D2, false, @moonnaga.Depth)
    "texture_depth_2d_array" =>
      self.types.image_type(@moonnaga.D2, true, @moonnaga.Depth)
    "texture_depth_cube" =>
      self.types.image_type(@moonnaga.Cube, false, @moonnaga.Depth)
    "texture_depth_cube_array" =>
      self.types.image_type(@moonnaga.Cube, true, @moonnaga.Depth)
    "texture_depth_multisampled_2d" =>
      self.types.image_type(@moonnaga.D2, false, @moonnaga.Depth)
    "texture_storage_1d"
    | "texture_storage_2d"
    | "texture_storage_2d_array"
    | "texture_storage_3d" => {
      let dim = if name == "texture_storage_2d" ||
        name == "texture_storage_2d_array" {
        @moonnaga.D2
      } else if name == "texture_storage_3d" {
        @moonnaga.D3
      } else {
        @moonnaga.D1
      }
      let arrayed = name == "texture_storage_2d_array"
      let format = if args.length() > 0 {
        match args[0] {
          Type(Named(format_name, _, _)) => format_name
          _ => fail("expected a texel format", span)
        }
      } else {
        fail("a storage texture needs a format", span)
      }
      let access = if args.length() > 1 {
        match args[1] {
          Type(Named(word, _, _)) =>
            match word {
              "read" => @moonnaga.Read
              "write" => @moonnaga.Write
              "read_write" => @moonnaga.ReadWrite
              // `atomic` marks a storage texture whose texels are atomic; the
              // access it implies is read-write.
              "atomic" => @moonnaga.ReadWrite
              other => fail("`\{other}` is not an access mode", span)
            }
          _ => fail("expected an access mode", span)
        }
      } else {
        @moonnaga.Write
      }
      self.types.image_type(
        dim,
        arrayed,
        @moonnaga.ImageClass::Storage(access, format),
      )
    }
    _ => fail("`\{name}` is not a texture type", span)
  }
}

///|
/// The integer value of a constant expression, for an array length or a template
/// argument.
fn Builder::const_int(self : Builder, expr : Expr) -> Int32 raise Failed {
  let span = expr_span(expr)
  // The expression is lowered where the type is being resolved, so a local
  // constant of the function is in scope; nothing here leaves the arena it is
  // called in.
  let handle = self.lower_value(expr)
  let value = self.fold(handle)
  match value {
    Some(Int(number)) => number.to_int()
    Some(_) => fail("expected an integer", span)
    None => fail("expected a constant expression", span)
  }
}

///|
/// Reads a number literal into the value and the type WGSL gives it.
fn literal_of_number(
  number : NumberLit,
  span : @moonnaga.Span,
) -> (@moonnaga.Literal, @moonnaga.Scalar) raise Failed {
  match number.suffix {
    Float => {
      let value = float_of_text(number.text, span)
      (@moonnaga.F32(Float::from_double(value)), @moonnaga.scalar_f32)
    }
    Half => {
      let value = float_of_text(number.text, span)
      (@moonnaga.F32(Float::from_double(value)), @moonnaga.float(2))
    }
    DoubleSuffix => {
      let value = float_of_text(number.text, span)
      (@moonnaga.F64(value), @moonnaga.scalar_f64)
    }
    LongSigned => {
      let value = integer_of_text(number.text, span, 10)
      (@moonnaga.I64(value), @moonnaga.scalar_i64)
    }
    LongUnsigned => {
      let value = integer_of_text(number.text, span, 10)
      (@moonnaga.U64(value.reinterpret_as_uint64()), @moonnaga.scalar_u64)
    }
    DoubleHalf => {
      let value = float_of_text(number.text, span)
      (@moonnaga.F64(value), @moonnaga.scalar_f64)
    }
    Signed => {
      let value = integer_of_text(number.text, span, 10)
      (@moonnaga.I32(value.to_int()), @moonnaga.scalar_i32)
    }
    Unsigned => {
      let value = integer_of_text(number.text, span, 10)
      (@moonnaga.U32(value.to_uint()), @moonnaga.scalar_u32)
    }
    Plain =>
      if number.is_float {
        let value = float_of_text(number.text, span)
        (
          @moonnaga.AbstractFloat(value),
          @moonnaga.Scalar::new(AbstractFloat, 8),
        )
      } else {
        let value = integer_of_text(number.text, span, 0)
        (@moonnaga.AbstractInt(value), @moonnaga.Scalar::new(AbstractInt, 8))
      }
  }
}

///|
/// The integer value of a literal, for the places that need one right away.
fn int_of_number(
  number : NumberLit,
  span : @moonnaga.Span,
) -> Int32 raise Failed {
  if number.is_float {
    return fail("expected an integer", span)
  }
  let radix = if number.text.has_prefix("0x") || number.text.has_prefix("0X") {
    0
  } else {
    10
  }
  integer_of_text(number.text, span, radix).to_int()
}

///|
/// Replaces a literal with one of another scalar type, which is how an abstract
/// literal picks up the width its context asks for.
fn Builder::coerce(
  self : Builder,
  handle : @moonnaga.Handle,
  target : @moonnaga.Handle,
) -> Unit {
  if self.type_of(handle) == target {
    return
  }
  let target_scalar = match self.shader().type_inner(target) {
    Scalar(scalar) => scalar
    _ => return
  }
  let expr = self.exprs.get(handle)
  match expr {
    @moonnaga.Literal(literal) => {
      let converted = convert_literal(literal, target_scalar)
      self.exprs.set(handle, @moonnaga.Literal(converted))
      self.kinds[handle.to_int()] = Plain(target)
    }
    @moonnaga.ZeroValue(_) => self.kinds[handle.to_int()] = Plain(target)
    _ => ()
  }
}

///|
fn convert_literal(
  literal : @moonnaga.Literal,
  target : @moonnaga.Scalar,
) -> @moonnaga.Literal {
  let as_double = match literal {
    AbstractInt(value) => value.to_double()
    AbstractFloat(value) => value
    I32(value) => value.to_double()
    U32(value) => value.to_double()
    F32(value) => value.to_double()
    F64(value) => value
    _ => 0.0
  }
  match target.kind {
    Float =>
      if target.width == 8 {
        F64(as_double)
      } else {
        F32(Float::from_double(as_double))
      }
    Sint => I32(as_double.to_int())
    Uint => U32(as_double.to_uint())
    Bool => Bool(as_double != 0.0)
    AbstractInt => AbstractInt(as_double.to_int64())
    AbstractFloat => AbstractFloat(as_double)
  }
}

///|
/// The concrete type an inferred type settles on: an abstract integer becomes
/// `i32` and an abstract float becomes `f32`, as WGSL specifies.
fn Builder::concretize(
  self : Builder,
  handle : @moonnaga.Handle,
) -> @moonnaga.Handle {
  match self.shader().type_inner(handle) {
    Scalar(scalar) =>
      if scalar.kind == AbstractInt {
        self.types.scalar_type(@moonnaga.scalar_i32)
      } else if scalar.kind == AbstractFloat {
        self.types.scalar_type(@moonnaga.scalar_f32)
      } else {
        handle
      }
    Vector(vector) =>
      if vector.scalar.is_abstract() {
        let scalar = if vector.scalar.kind == AbstractInt {
          @moonnaga.scalar_i32
        } else {
          @moonnaga.scalar_f32
        }
        self.types.vector_type(vector.size, scalar)
      } else {
        handle
      }
    Matrix(matrix) =>
      if matrix.scalar.is_abstract() {
        self.types.matrix_type(
          matrix.columns,
          matrix.rows,
          @moonnaga.scalar_f32,
        )
      } else {
        handle
      }
    _ => handle
  }
}

///|
fn Builder::zero_value(
  self : Builder,
  ty : @moonnaga.Handle,
) -> @moonnaga.Handle {
  self.emit(@moonnaga.ZeroValue(ty), Plain(ty))
}
