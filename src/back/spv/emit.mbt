// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The id of a type, written the first time it is asked for.
fn Writer::type_word(
  self : Writer,
  handle : @moonnaga.Handle,
) -> Word raise SpvError {
  match self.type_ids.get(handle.to_int()) {
    Some(id) => return id
    None => ()
  }
  let ty = self.shader.types.get(handle)
  let id = match ty.inner {
    @moonnaga.Scalar(scalar) => self.scalar_word(scalar)
    @moonnaga.Vector(vector) => {
      let component = self.scalar_word(vector.scalar)
      self.builder.emit_typed(op_type_vector, [
        component,
        vector.size.to_int().reinterpret_as_uint(),
      ])
    }
    @moonnaga.Matrix(matrix) => {
      let column = self.type_word(
        self.vector_handle(matrix.rows, matrix.scalar),
      )
      self.builder.emit_typed(op_type_matrix, [
        column,
        matrix.columns.to_int().reinterpret_as_uint(),
      ])
    }
    @moonnaga.Atomic(scalar) => self.scalar_word(scalar)
    @moonnaga.Pointer(pointer) => {
      let base = self.type_word(pointer.base)
      let class_ = self.storage_class(pointer.space)
      self.builder.emit_typed(op_type_pointer, [class_, base])
    }
    @moonnaga.Array(array) => {
      let element = self.type_word(array.base)
      let id = match array.size {
        @moonnaga.Fixed(count) => {
          let length = self.uint_constant(count.reinterpret_as_uint())
          self.builder.emit_typed(op_type_array, [element, length])
        }
        // An array whose length the bound buffer decides is a runtime array,
        // which only a buffer can hold.
        _ => self.builder.emit_typed(op_type_runtime_array, [element])
      }
      if array.stride > 0 {
        self.builder.emit(op_decorate, [
          id,
          decoration_array_stride,
          array.stride.reinterpret_as_uint(),
        ])
      }
      id
    }
    @moonnaga.Struct(structure) => {
      let members = []
      for field in structure.members {
        members.push(self.type_word(field.ty))
      }
      let id = self.builder.emit_typed(op_type_struct, members)
      self.builder.emit(op_decorate, [id, decoration_block])
      for index in 0..<structure.members.length() {
        let field = structure.members[index]
        self.builder.emit(
          op_member_decorate,
          [
            id,
            index.reinterpret_as_uint(),
            35,
            field.offset.reinterpret_as_uint(),
          ], // Offset
        )
        match field.binding {
          Some(@moonnaga.BuiltIn(builtin)) =>
            self.builder.emit(op_member_decorate, [
              id,
              index.reinterpret_as_uint(),
              decoration_builtin,
              builtin_word(builtin),
            ])
          Some(@moonnaga.Location(location)) =>
            self.builder.emit(op_member_decorate, [
              id,
              index.reinterpret_as_uint(),
              decoration_location,
              location.reinterpret_as_uint(),
            ])
          None => ()
        }
      }
      id
    }
    @moonnaga.Image(image) => self.image_word(image)
    @moonnaga.Sampler(_) => self.builder.emit_typed(op_type_sampler, [])
    @moonnaga.AccelerationStructure(_) =>
      unsupported("an acceleration structure")
    @moonnaga.RayQuery(_) => unsupported("a ray query")
    @moonnaga.BindingArray(_) => unsupported("a binding array")
    @moonnaga.ValuePointer(_) => unsupported("a value pointer")
  }
  self.type_ids[handle.to_int()] = id
  id
}

///|
fn Writer::scalar_word(
  self : Writer,
  scalar : @moonnaga.Scalar,
) -> Word raise SpvError {
  // One instruction per distinct scalar: a shader that uses `f32` both on its own
  // and inside a vector may not declare it twice.
  let key = @moonnaga.scalar_name(scalar)
  match self.scalar_ids.get(key) {
    Some(id) => return id
    None => ()
  }
  let id = match scalar.kind {
    @moonnaga.Bool => {
      if self.bool_id == 0 {
        self.bool_id = self.builder.emit_typed(op_type_bool, [])
      }
      self.bool_id
    }
    @moonnaga.Sint =>
      self.builder.emit_typed(op_type_int, [
        (scalar.width * 8).reinterpret_as_uint(),
        1,
      ])
    @moonnaga.Uint =>
      self.builder.emit_typed(op_type_int, [
        (scalar.width * 8).reinterpret_as_uint(),
        0,
      ])
    @moonnaga.Float =>
      self.builder.emit_typed(op_type_float, [
        (scalar.width * 8).reinterpret_as_uint(),
      ])
    @moonnaga.AbstractInt | @moonnaga.AbstractFloat =>
      unsupported("an abstract type reaching a back end")
  }
  self.scalar_ids[key] = id
  id
}

///|
/// The module type of a vector, so the writer can name it without the caller
/// having to have interned one.
fn Writer::vector_handle(
  self : Writer,
  size : @moonnaga.VectorSize,
  scalar : @moonnaga.Scalar,
) -> @moonnaga.Handle raise SpvError {
  for index in 0..<self.shader.types.len() {
    let handle = @moonnaga.Handle::new(index)
    match self.shader.types.get(handle).inner {
      @moonnaga.Vector(vector) =>
        if vector.size == size && vector.scalar == scalar {
          return handle
        }
      _ => ()
    }
  }
  unsupported("a vector type the shader never declared")
}

///|
fn Writer::image_word(
  self : Writer,
  image : @moonnaga.ImageType,
) -> Word raise SpvError {
  let sampled = match image.class {
    @moonnaga.Storage(_, format) => storage_scalar_name(format)
    @moonnaga.Depth => @moonnaga.scalar_f32
    @moonnaga.Sampling => @moonnaga.scalar_f32
  }
  let sampled_type = self.scalar_word(sampled)
  let dim : Word = match image.dim {
    @moonnaga.D1 => 0
    @moonnaga.D2 => 1
    @moonnaga.D3 => 2
    @moonnaga.Cube => 3
  }
  let depth : Word = match image.class {
    @moonnaga.Depth => 1
    _ => 0
  }
  let arrayed : Word = if image.arrayed { 1 } else { 0 }
  let sampled_flag : Word = match image.class {
    @moonnaga.Storage(_, _) => 2
    _ => 1
  }
  let format : Word = match image.class {
    @moonnaga.Storage(_, name) => image_format_word(name)
    _ => 0
  }
  let access : Word = 0
  self.builder.emit_typed(op_type_image, [
    sampled_type, dim, depth, arrayed, 0, sampled_flag, format, access,
  ])
}

///|
fn storage_scalar_name(format : String) -> @moonnaga.Scalar {
  if format.has_suffix("uint") {
    @moonnaga.scalar_u32
  } else if format.has_suffix("sint") {
    @moonnaga.scalar_i32
  } else {
    @moonnaga.scalar_f32
  }
}

///|
fn image_format_word(format : String) -> Word {
  match format {
    "rgba8unorm" => 4
    "rgba8snorm" => 5
    "rgba8uint" => 8
    "rgba8sint" => 9
    "r16float" => 14
    "r32float" => 17
    "r32uint" => 21
    "r32sint" => 22
    "rgba16float" => 27
    "rgba32float" => 30
    "rgba32uint" => 34
    "rgba32sint" => 35
    _ => 0
  }
}

///|
fn Writer::storage_class(
  _self : Writer,
  space : @moonnaga.AddressSpace,
) -> Word {
  match space {
    @moonnaga.Function => class_function
    @moonnaga.Private => class_private
    @moonnaga.WorkGroup => class_workgroup
    @moonnaga.Uniform => class_uniform
    @moonnaga.Storage(_) => class_storage_buffer
    @moonnaga.PushConstant => class_push_constant
    @moonnaga.Handle => class_uniform_constant
  }
}

///|
pub fn builtin_word(builtin : @moonnaga.BuiltIn) -> Word {
  match builtin {
    @moonnaga.Position(_) => builtin_position
    @moonnaga.PointSize => builtin_point_size
    @moonnaga.ClipDistance => builtin_clip_distance
    @moonnaga.CullDistance => builtin_cull_distance
    @moonnaga.PrimitiveIndex => builtin_primitive_id
    @moonnaga.PointCoord => builtin_point_coord
    @moonnaga.FrontFacing => builtin_front_facing
    @moonnaga.SampleIndex => builtin_sample_id
    @moonnaga.SampleMask => builtin_sample_mask
    @moonnaga.FragDepth => builtin_frag_depth
    @moonnaga.NumWorkgroups => builtin_num_workgroups
    @moonnaga.WorkgroupSize => builtin_workgroup_size
    @moonnaga.WorkgroupId => builtin_workgroup_id
    @moonnaga.LocalInvocationId => builtin_local_invocation_id
    @moonnaga.GlobalInvocationId => builtin_global_invocation_id
    @moonnaga.LocalInvocationIndex => builtin_local_invocation_index
    @moonnaga.VertexIndex => builtin_vertex_index
    @moonnaga.InstanceIndex => builtin_instance_index
    @moonnaga.DrawId => builtin_draw_index
    @moonnaga.ViewIndex => builtin_view_index
    _ => 0
  }
}

///|
/// An unsigned 32-bit constant, which array lengths and sizes need.
fn Writer::uint_constant(self : Writer, value : Word) -> Word raise SpvError {
  let ty = self.uint_type()
  self.builder.emit_result(op_constant, ty, [value])
}

///|
/// The module's own `u32`, so an index constant shares one type with the shader
/// instead of declaring a second integer of the same shape.
fn Writer::uint_type(self : Writer) -> Word raise SpvError {
  for index in 0..<self.shader.types.len() {
    let handle = @moonnaga.Handle::new(index)
    match self.shader.types.get(handle).inner {
      @moonnaga.Scalar(scalar) =>
        if scalar.kind == @moonnaga.Uint && scalar.width == 4 {
          return self.type_word(handle)
        }
      _ => ()
    }
  }
  if self.uint_id == 0 {
    self.uint_id = self.builder.emit_typed(op_type_int, [32U, 0U])
  }
  self.uint_id
}

///|
/// The id of a literal or of a constant expression.
fn Writer::const_word(
  self : Writer,
  handle : @moonnaga.Handle,
  ty : @moonnaga.Handle,
) -> Word raise SpvError {
  match self.const_ids.get(handle.to_int()) {
    Some(id) => return id
    None => ()
  }
  let expr = self.shader.const_expressions.get(handle)
  let id = match expr {
    @moonnaga.Literal(literal) => {
      let type_id = self.type_word(ty)
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
    }
    @moonnaga.ZeroValue(zero_type) =>
      self.builder.emit_result(op_constant_null, self.type_word(zero_type), [])
    @moonnaga.Compose(compose) => {
      let components = []
      for component in compose.components {
        let component_type = match self.shader.types.get(compose.ty).inner {
          @moonnaga.Vector(vector) =>
            self.vector_scalar_handle(compose.ty, vector.scalar)
          @moonnaga.Array(array) => array.base
          @moonnaga.Struct(structure) =>
            structure.members[components.length()].ty
          @moonnaga.Matrix(matrix) =>
            self.vector_handle(matrix.rows, matrix.scalar)
          _ => compose.ty
        }
        components.push(self.const_word(component, component_type))
      }
      self.builder.emit_result(
        op_constant_composite,
        self.type_word(compose.ty),
        components,
      )
    }
    @moonnaga.Constant(constant) => {
      let entry = self.shader.constants.get(constant)
      self.const_word(entry.init, entry.ty)
    }
    _ => unsupported("a constant expression this build cannot fold")
  }
  self.const_ids[handle.to_int()] = id
  id
}

///|
fn Writer::vector_scalar_handle(
  self : Writer,
  _vector : @moonnaga.Handle,
  scalar : @moonnaga.Scalar,
) -> @moonnaga.Handle raise SpvError {
  for index in 0..<self.shader.types.len() {
    let handle = @moonnaga.Handle::new(index)
    match self.shader.types.get(handle).inner {
      @moonnaga.Scalar(found) => if found == scalar { return handle }
      _ => ()
    }
  }
  unsupported("a scalar type the shader never declared")
}

///|
fn Writer::global_id(self : Writer, handle : @moonnaga.Handle) -> Word {
  match self.global_ids.get(handle.to_int()) {
    Some(id) => id
    None => 0
  }
}

///|
fn Writer::write_globals(self : Writer) -> Unit raise SpvError {
  for index in 0..<self.shader.global_variables.len() {
    let handle = @moonnaga.Handle::new(index)
    let global = self.shader.global_variables.get(handle)
    let base = self.type_word(global.ty)
    // A buffer variable has to be a struct: a shader that binds a bare array
    // gets a struct of one member wrapped around it.
    let base = match global.space {
      @moonnaga.Storage(_) | @moonnaga.Uniform =>
        match self.shader.type_inner(global.ty) {
          @moonnaga.Struct(_) => base
          _ => {
            let wrapper = self.builder.emit_typed(op_type_struct, [base])
            self.builder.emit(op_decorate, [wrapper, decoration_block])
            self.builder.emit(
              op_member_decorate,
              [wrapper, 0U, 35U, 0U], // Offset 0
            )
            self.wrapped[index] = wrapper
            wrapper
          }
        }
      _ => base
    }
    let class_ = self.storage_class(global.space)
    let pointer = self.builder.emit_typed(op_type_pointer, [class_, base])
    let id = self.global_ids.get(index).unwrap_or(0)
    ignore(self.builder.emit_result_with_id(op_variable, id, pointer, [class_]))
    let name = match global.name {
      Some(name) => name
      None => "global" + index.to_string()
    }
    self.builder.emit(op_name, [id] + string_words(name))
  }
}

///|
fn Writer::write_decorations_for_globals(self : Writer) -> Unit {
  for index in 0..<self.shader.global_variables.len() {
    let global = self.shader.global_variables.get(@moonnaga.Handle::new(index))
    let id = self.global_ids.get(index).unwrap_or(0)
    match global.binding {
      Some(binding) => {
        self.builder.emit(op_decorate, [
          id,
          decoration_descriptor_set,
          binding.group.reinterpret_as_uint(),
        ])
        self.builder.emit(op_decorate, [
          id,
          decoration_binding,
          binding.binding.reinterpret_as_uint(),
        ])
      }
      None => ()
    }
  }
}

///|
/// The low 32 bits of a 64-bit word, which is how a 64-bit constant is written.
fn low_word(value : UInt64) -> Word {
  (value & 0xFFFFFFFFUL).to_uint()
}

///|
/// The high 32 bits of a 64-bit word.
fn high_word(value : UInt64) -> Word {
  (value >> 32).to_uint()
}
