// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The writer's state for one module: the words being built, the ids handed out
/// so far, and the caches that keep one entry per type and per constant.
pub(all) struct Writer {
  shader : @moonnaga.Module
  builder : Builder
  options : Options
  type_ids : Map[Int32, Word]
  const_ids : Map[Int32, Word]
  global_ids : Map[Int32, Word]
  function_ids : Map[Int32, Word]
  mut expr_ids : Map[Int32, Word]
  mut blocks : Array[Word]
  mut void_id : Word
  mut bool_id : Word
  mut glsl_id : Word
  mut uint_id : Word
  scalar_ids : Map[String, Word]
  /// Globals whose declared type had to be wrapped in a struct, which is what a
  /// buffer variable must be. The value is the id of the wrapper.
  wrapped : Map[Int32, Word]
  mut terminated : Bool
  mut break_target : Word
  mut continue_target : Word
  mut switch_merge : Word
  mut argument_ids : Array[Word]
  mut local_ids : Map[Int32, Word]
  mut targets : Array[Targets]
  mut current : @moonnaga.Function?
  /// The variables an entry point reads its arguments from and writes its result
  /// to. A Vulkan entry point takes no parameters: its interface is global.
  mut interface_loads : Array[Word]
  mut interface_result : Word
  /// The interface variables of every entry point, created before any function
  /// so they land in the global section the format reserves for them.
  interface_inputs : Map[Int32, Array[Word]]
  interface_outputs : Map[Int32, Word]
}

///|
pub fn Writer::new(shader : @moonnaga.Module, options : Options) -> Writer {
  {
    shader,
    builder: Builder::new(),
    options,
    type_ids: Map([]),
    const_ids: Map([]),
    global_ids: Map([]),
    function_ids: Map([]),
    void_id: 0,
    bool_id: 0,
    glsl_id: 0,
    uint_id: 0,
    scalar_ids: Map([]),
    wrapped: Map([]),
    expr_ids: Map([]),
    blocks: [],
    terminated: false,
    break_target: 0,
    continue_target: 0,
    switch_merge: 0,
    argument_ids: [],
    local_ids: Map([]),
    targets: [],
    current: None,
    interface_loads: [],
    interface_result: 0,
    interface_inputs: Map([]),
    interface_outputs: Map([]),
  }
}

///|
/// Translates a module into a SPIR-V binary.
pub fn write_module(
  shader : @moonnaga.Module,
  info : @valid.ModuleInfo,
  options~ : Options = options_default,
) -> Array[Byte] raise SpvError {
  let writer = Writer::new(shader, options)
  writer.write_header()
  writer.allocate_global_ids()
  writer.allocate_interface_ids()
  writer.write_entry_points(info)
  writer.builder.start_body()
  writer.write_decorations_for_globals()
  writer.write_interface_variables()
  writer.write_globals()
  writer.write_functions()
  writer.builder.to_bytes()
}

///|
fn Writer::write_header(self : Writer) -> Unit {
  let builder = self.builder
  builder.set_version(self.options.version)
  builder.emit(op_capability, [1U]) // Shader
  if self.uses_capability("f64") {
    builder.emit(op_capability, [10U]) // Float64
  }
  if self.uses_capability("i64") {
    builder.emit(op_capability, [11U]) // Int64
  }
  let glsl = builder.emit_typed(
    op_ext_inst_import,
    string_words("GLSL.std.450"),
  )
  self.glsl_id = glsl
  builder.emit(op_memory_model, [0U, 1U]) // Logical, GLSL450
  ignore(self.options)
}

///|
/// Whether the module uses a type that needs an extra capability.
fn Writer::uses_capability(self : Writer, feature : String) -> Bool {
  for index in 0..<self.shader.types.len() {
    let ty = self.shader.types.get(@moonnaga.Handle::new(index))
    let scalar = match ty.inner {
      @moonnaga.Scalar(scalar) => Some(scalar)
      @moonnaga.Vector(vector) => Some(vector.scalar)
      @moonnaga.Matrix(matrix) => Some(matrix.scalar)
      @moonnaga.Atomic(scalar) => Some(scalar)
      _ => None
    }
    match scalar {
      Some(scalar) => {
        let is_wide_float = scalar.kind == @moonnaga.Float && scalar.width == 8
        let is_wide_integer = (
            scalar.kind == @moonnaga.Sint || scalar.kind == @moonnaga.Uint
          ) &&
          scalar.width == 8
        if feature == "f64" && is_wide_float {
          return true
        }
        if feature == "i64" && is_wide_integer {
          return true
        }
      }
      None => ()
    }
  }
  false
}

///|
/// One `OpEntryPoint` per entry point, with the globals it can reach listed as
/// its interface.
fn Writer::write_entry_points(self : Writer, info : @valid.ModuleInfo) -> Unit {
  for entry in info.entry_points {
    let function = self.function_id(entry.function)
    let model : Word = match entry.stage {
      @moonnaga.Vertex => 0
      @moonnaga.Fragment => 4
      @moonnaga.Compute => 5
      @moonnaga.Task => 5364
      @moonnaga.Mesh => 5365
    }
    // Up to SPIR-V 1.4 an entry point's interface lists only its inputs and
    // outputs; buffers reach it through their bindings.
    let interface : Array[Word] = []
    match self.interface_inputs.get(entry.function.to_int()) {
      Some(inputs) =>
        for id in inputs {
          interface.push(id)
        }
      None => ()
    }
    match self.interface_outputs.get(entry.function.to_int()) {
      Some(id) => interface.push(id)
      None => ()
    }
    let words : Array[Word] = [model, function]
    for word in string_words(entry.name) {
      words.push(word)
    }
    for id in interface {
      words.push(id)
    }
    self.builder.emit(op_entry_point, words)
    if entry.stage == @moonnaga.Compute {
      self.builder.emit(op_execution_mode, [
        function,
        17U, // LocalSize
        entry.workgroup_size[0].reinterpret_as_uint(),
        entry.workgroup_size[1].reinterpret_as_uint(),
        entry.workgroup_size[2].reinterpret_as_uint(),
      ])
    }
  }
}

///|
/// Hands out an id per global before any instruction is written: an entry point
/// lists the globals it can reach, and that list comes before the variables
/// themselves.
fn Writer::allocate_global_ids(self : Writer) -> Unit {
  for index in 0..<self.shader.global_variables.len() {
    let id = self.builder.next()
    self.global_ids[index] = id
  }
}

///|
/// The id of a function, handed out before any body is written so an entry point
/// can name a function declared later.
fn Writer::function_id(self : Writer, handle : @moonnaga.Handle) -> Word {
  match self.function_ids.get(handle.to_int()) {
    Some(id) => id
    None => {
      let id = self.builder.next()
      self.function_ids[handle.to_int()] = id
      id
    }
  }
}

///|
/// Hands out the ids of the interface variables before the entry points that
/// list them are written. The variables themselves are declared with the other
/// globals.
fn Writer::allocate_interface_ids(self : Writer) -> Unit {
  for entry in self.shader.entry_points {
    let function = self.shader.functions.get(entry.function)
    let inputs = []
    for _ in 0..<function.arguments.length() {
      inputs.push(self.builder.next())
    }
    self.interface_inputs[entry.function.to_int()] = inputs
    match function.result.ty {
      Some(_) =>
        self.interface_outputs[entry.function.to_int()] = self.builder.next()
      None => ()
    }
  }
}

///|
/// Declares the global variables an entry point takes its arguments from and
/// leaves its result in.
fn Writer::write_interface_variables(self : Writer) -> Unit raise SpvError {
  for entry in self.shader.entry_points {
    let function = self.shader.functions.get(entry.function)
    let inputs = self.interface_inputs
      .get(entry.function.to_int())
      .unwrap_or([])
    for index in 0..<function.arguments.length() {
      let argument = function.arguments[index]
      let base = self.type_word(argument.ty)
      let pointer = self.builder.emit_typed(op_type_pointer, [class_input, base])
      let variable = inputs[index]
      ignore(
        self.builder.emit_result_with_id(op_variable, variable, pointer, [
          class_input,
        ]),
      )
      self.decorate_interface(variable, argument.binding, argument.interpolate)
      let name = match argument.name {
        Some(name) => name
        None => "in" + index.to_string()
      }
      self.builder.emit(op_name, [variable] + string_words(name))
    }
    match function.result.ty {
      Some(ty) => {
        let base = self.type_word(ty)
        let pointer = self.builder.emit_typed(op_type_pointer, [
          class_output, base,
        ])
        let variable = self.interface_outputs
          .get(entry.function.to_int())
          .unwrap_or(0)
        ignore(
          self.builder.emit_result_with_id(op_variable, variable, pointer, [
            class_output,
          ]),
        )
        self.decorate_interface(
          variable,
          function.result.binding,
          function.result.interpolate,
        )
        self.builder.emit(op_name, [variable] + string_words("out"))
      }
      None => ()
    }
  }
}
