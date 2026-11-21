// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Lowers a call: a type constructor, a function the module declares, or one of
/// the builtins the language predeclares.
fn Builder::lower_call(
  self : Builder,
  name : String,
  type_args : Array[TemplateArg],
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match self.construct(name, type_args, args, span) {
    Some(handle) => return handle
    None => ()
  }
  if name == "bitcast" {
    if type_args.is_empty() {
      return fail("`bitcast` needs a target type", span)
    }
    return self.lower_bitcast(type_args, args[0], span)
  }
  match self.signatures.get(name) {
    Some(signature) => return self.call_function(name, signature, args, span)
    None => ()
  }
  self.call_builtin(name, args, span)
}

///|
/// A call to a function the module declares. The call becomes a statement, and
/// the value it produces an expression that names the result.
fn Builder::call_function(
  self : Builder,
  name : String,
  signature : FnSignature,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  if args.length() != signature.params.length() {
    return fail("`\{name}` takes \{signature.params.length()} arguments", span)
  }
  let lowered = []
  for index in 0..<args.length() {
    let value = self.lower_value(args[index])
    self.coerce(value, signature.params[index])
    lowered.push(value)
  }
  let result = match signature.result {
    Some(ty) =>
      Some(self.emit(@moonnaga.CallResult(signature.handle), Plain(ty)))
    None => None
  }
  self.emits.push(
    @moonnaga.Call({ function: signature.handle, arguments: lowered, result, }),
  )
  match result {
    Some(handle) => handle
    None =>
      self.emit(
        @moonnaga.ZeroValue(self.types.scalar_type(@moonnaga.boolean())),
        Plain(self.types.scalar_type(@moonnaga.boolean())),
      )
  }
}

///|
/// Whether a call names something whose only effect is a statement, so the
/// statement form needs no `@moonnaga.Emit`.
pub fn is_void_call(name : String) -> Bool {
  match name {
    "textureStore"
    | "atomicStore"
    | "workgroupBarrier"
    | "storageBarrier"
    | "textureBarrier" => true
    _ => false
  }
}

///|
/// The scalar type a name writes, if it is one.
fn scalar_by_name(name : String) -> @moonnaga.Scalar? {
  match name {
    "i32" => Some(@moonnaga.scalar_i32)
    "u32" => Some(@moonnaga.scalar_u32)
    "f32" => Some(@moonnaga.scalar_f32)
    "f64" => Some(@moonnaga.scalar_f64)
    "i64" => Some(@moonnaga.scalar_i64)
    "u64" => Some(@moonnaga.scalar_u64)
    "f16" => Some(@moonnaga.float(2))
    "bool" => Some(@moonnaga.boolean())
    _ => None
  }
}

///|
/// A call that names a type: a scalar conversion, a vector or matrix
/// constructor, an array, or a struct.
fn Builder::construct(
  self : Builder,
  name : String,
  type_args : Array[TemplateArg],
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle? raise Failed {
  match scalar_by_name(name) {
    Some(scalar) => {
      let ty = self.types.scalar_type(scalar)
      if args.is_empty() {
        return Some(self.zero_value(ty))
      }
      let value = self.lower_value(args[0])
      let source = self.shader().scalar_of(self.type_of(value))
      match source {
        Some(source) =>
          if source == scalar {
            Some(value)
          } else {
            let converted = self.emit(
              @moonnaga.As({
                expr: value,
                kind: scalar.kind,
                convert: Some(scalar.width),
              }),
              Plain(ty),
            )
            Some(converted)
          }
        None => Some(value)
      }
    }
    None =>
      if name == "vec2f" ||
        name == "vec3f" ||
        name == "vec4f" ||
        name == "vec2i" ||
        name == "vec3i" ||
        name == "vec4i" ||
        name == "vec2u" ||
        name == "vec3u" ||
        name == "vec4u" {
        let size = match name {
          "vec2f" | "vec2i" | "vec2u" => @moonnaga.Bi
          "vec3f" | "vec3i" | "vec3u" => @moonnaga.Tri
          _ => @moonnaga.Quad
        }
        let _scalar = match name {
          "vec2i" | "vec3i" | "vec4i" => @moonnaga.scalar_i32
          "vec2u" | "vec3u" | "vec4u" => @moonnaga.scalar_u32
          _ => @moonnaga.scalar_f32
        }
        Some(
          self.vector_constructor(
            size,
            [Type(Named("f32", [], @moonnaga.Span::new(0, 0)))],
            args,
            span,
          ),
        )
      } else if name == "vec2" || name == "vec3" || name == "vec4" {
        let size = match name {
          "vec2" => @moonnaga.Bi
          "vec3" => @moonnaga.Tri
          _ => @moonnaga.Quad
        }
        Some(self.vector_constructor(size, type_args, args, span))
      } else if name == "mat2x2" ||
        name == "mat2x3" ||
        name == "mat2x4" ||
        name == "mat3x2" ||
        name == "mat3x3" ||
        name == "mat3x4" ||
        name == "mat4x2" ||
        name == "mat4x3" ||
        name == "mat4x4" {
        Some(self.matrix_constructor(name, type_args, args, span))
      } else if name == "array" {
        Some(self.array_constructor(type_args, args, span))
      } else {
        match self.types.lookup(name) {
          Some(handle) =>
            match self.shader().type_inner(handle) {
              Struct(_) =>
                Some(self.struct_constructor(name, handle, args, span))
              _ => None
            }
          None => None
        }
      }
  }
}

///|
fn Builder::vector_constructor(
  self : Builder,
  size : @moonnaga.VectorSize,
  type_args : Array[TemplateArg],
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let wanted = size.to_int()
  // With no template argument the element type comes from the components, which
  // is what makes `vec4(1, 2, 3, 4)` an abstract vector.
  let component_handles = []
  for arg in args {
    component_handles.push(self.lower_value(arg))
  }
  let scalar = if type_args.is_empty() {
    let mut scalar = @moonnaga.scalar_i32
    for handle in component_handles {
      match self.shader().scalar_of(self.type_of(handle)) {
        Some(found) => scalar = found
        None => ()
      }
    }
    scalar
  } else {
    match type_args[0] {
      Type(expr) =>
        match self.shader().type_inner(self.resolve_type(expr)) {
          Scalar(scalar) => scalar
          _ => fail("a vector takes a scalar type", span)
        }
      Expr(_) => fail("a vector takes a scalar type", span)
    }
  }
  let ty = self.types.vector_type(size, scalar)
  let scalar_ty = self.types.scalar_type(scalar)
  if component_handles.is_empty() {
    return self.zero_value(ty)
  }
  if component_handles.length() == 1 {
    let only = component_handles[0]
    self.coerce(only, scalar_ty)
    return self.emit(@moonnaga.Splat({ size, value: only, }), Plain(ty))
  }
  let components = []
  let mut total = 0
  for handle in component_handles {
    let count = match self.shader().components_of(self.type_of(handle)) {
      Some(count) => count
      None => 1
    }
    total = total + count
    match self.shader().type_inner(self.type_of(handle)) {
      Scalar(_) => self.coerce(handle, scalar_ty)
      _ => ()
    }
    components.push(handle)
  }
  if total != wanted {
    return fail(
      "a `\{name_of_vector(wanted)}` needs \{wanted} components",
      span,
    )
  }
  self.emit(@moonnaga.Compose({ ty, components, }), Plain(ty))
}

///|
fn name_of_vector(size : Int32) -> String {
  "vec\{size}"
}

///|
fn Builder::matrix_constructor(
  self : Builder,
  name : String,
  type_args : Array[TemplateArg],
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
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
  let scalar = if type_args.is_empty() {
    @moonnaga.scalar_f32
  } else {
    match type_args[0] {
      Type(expr) =>
        match self.shader().type_inner(self.resolve_type(expr)) {
          Scalar(scalar) => scalar
          _ => fail("a matrix takes a scalar type", span)
        }
      Expr(_) => fail("a matrix takes a scalar type", span)
    }
  }
  let ty = self.types.matrix_type(columns, rows, scalar)
  if args.is_empty() {
    return self.zero_value(ty)
  }
  // A matrix is a composition of its columns, and a column may be written as a
  // vector or as the scalars that make it up.
  let column_ty = self.types.vector_type(rows, scalar)
  let column_scalar = self.types.scalar_type(scalar)
  let lowered = []
  for arg in args {
    lowered.push(self.lower_value(arg))
  }
  let components = []
  if lowered.length() == 1 &&
    self.shader().components_of(self.type_of(lowered[0])) == Some(1) {
    self.coerce(lowered[0], column_scalar)
    for _ in 0..<columns.to_int() {
      components.push(
        self.emit(
          @moonnaga.Splat({ size: rows, value: lowered[0], }),
          Plain(column_ty),
        ),
      )
    }
  } else if lowered.length() == columns.to_int() {
    for handle in lowered {
      self.coerce(handle, column_ty)
      components.push(handle)
    }
  } else {
    let column_components = []
    for handle in lowered {
      column_components.push(handle)
    }
    let mut index = 0
    let scalars = column_components.length()
    let needed = columns.to_int() * rows.to_int()
    if scalars != needed {
      return fail("a matrix needs its columns or its scalars", span)
    }
    while index < scalars {
      let parts = []
      for offset in 0..<rows.to_int() {
        let handle = column_components[index + offset]
        self.coerce(handle, column_scalar)
        parts.push(handle)
      }
      components.push(
        self.emit(
          @moonnaga.Compose({ ty: column_ty, components: parts, }),
          Plain(column_ty),
        ),
      )
      index = index + rows.to_int()
    }
  }
  self.emit(@moonnaga.Compose({ ty, components, }), Plain(ty))
}

///|
fn Builder::array_constructor(
  self : Builder,
  type_args : Array[TemplateArg],
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let mut element = None
  for arg in type_args {
    match arg {
      Type(expr) => element = Some(self.resolve_type(expr))
      Expr(_) => ()
    }
  }
  let lowered = []
  for arg in args {
    lowered.push(self.lower_value(arg))
  }
  let element = match element {
    Some(handle) => handle
    None =>
      if lowered.is_empty() {
        return fail("an array construct needs its elements", span)
      } else {
        self.type_of(lowered[0])
      }
  }
  for handle in lowered {
    self.coerce(handle, element)
  }
  let size = match type_args.length() {
    2 =>
      match type_args[1] {
        Expr(expr) => @moonnaga.Fixed(self.const_int(expr))
        Type(_) => @moonnaga.Fixed(lowered.length())
      }
    _ => @moonnaga.Fixed(lowered.length())
  }
  let ty = self.types.array_type(element, size)
  if lowered.is_empty() {
    return self.zero_value(ty)
  }
  match size {
    @moonnaga.Fixed(count) =>
      if count != lowered.length() {
        return fail("the array has \{count} elements", span)
      }
    _ => ()
  }
  self.emit(@moonnaga.Compose({ ty, components: lowered, }), Plain(ty))
}

///|
fn Builder::struct_constructor(
  self : Builder,
  name : String,
  ty : @moonnaga.Handle,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let structure = match self.shader().type_inner(ty) {
    Struct(structure) => structure
    _ => fail("`\{name}` is not a struct", span)
  }
  if args.is_empty() {
    return self.zero_value(ty)
  }
  if args.length() != structure.members.length() {
    return fail("`\{name}` has \{structure.members.length()} members", span)
  }
  let components = []
  for index in 0..<args.length() {
    let value = self.lower_value(args[index])
    self.coerce(value, structure.members[index].ty)
    components.push(value)
  }
  self.emit(@moonnaga.Compose({ ty, components, }), Plain(ty))
}

///|
fn Builder::lower_bitcast(
  self : Builder,
  type_args : Array[TemplateArg],
  inner : Expr,
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  if type_args.is_empty() {
    return fail("`bitcast` needs a target type", span)
  }
  let target = self.resolve_type_arg(type_args[0], span)
  let value = self.lower_value(inner)
  self.emit(
    @moonnaga.As({ expr: value, kind: @moonnaga.Sint, convert: None, }),
    Plain(target),
  )
}
