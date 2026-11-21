// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The control-flow targets a `break` or a `continue` jumps to.
pub(all) struct Targets {
  break_to : Word
  continue_to : Word
}

///|
fn Writer::write_functions(self : Writer) -> Unit raise SpvError {
  for index in 0..<self.shader.functions.len() {
    let handle = @moonnaga.Handle::new(index)
    self.write_function(handle, self.shader.functions.get(handle))
  }
}

///|
fn Writer::write_function(
  self : Writer,
  handle : @moonnaga.Handle,
  function : @moonnaga.Function,
) -> Unit raise SpvError {
  if self.void_id == 0 {
    self.void_id = self.builder.emit_typed(op_type_void, [])
  }
  // An entry point returns nothing and takes nothing: its interface is global.
  let is_entry = self.entry_for(handle)
  let result_type = if is_entry {
    self.void_id
  } else {
    match function.result.ty {
      Some(ty) => self.type_word(ty)
      None => self.void_id
    }
  }
  let parameter_types = []
  if !is_entry {
    for argument in function.arguments {
      parameter_types.push(self.type_word(argument.ty))
    }
  }
  let function_type = self.builder.emit_typed(
    op_type_function,
    [result_type] + parameter_types,
  )
  let id = self.function_id(handle)
  self.expr_ids = Map([])
  self.blocks = []
  self.current = Some(function)
  self.builder.emit(op_function, [result_type, id, 0, function_type])
  let name = match function.name {
    Some(name) => name
    None => "function" + handle.to_int().to_string()
  }
  self.builder.emit(op_name, [id] + string_words(name))
  let parameter_ids = []
  if is_entry {
    // The interface variables were created with the globals; the function only
    // needs their ids.
    match self.interface_inputs.get(handle.to_int()) {
      Some(inputs) =>
        for id in inputs {
          parameter_ids.push(id)
        }
      None => ()
    }
    self.interface_loads = parameter_ids
    self.interface_result = self.interface_outputs
      .get(handle.to_int())
      .unwrap_or(0)
  } else {
    for index in 0..<function.arguments.length() {
      let argument = function.arguments[index]
      let parameter = self.builder.next()
      self.builder.emit(op_function_parameter, [
        self.type_word(argument.ty),
        parameter,
      ])
      let argument_name = match argument.name {
        Some(name) => name
        None => "arg" + index.to_string()
      }
      self.builder.emit(op_name, [parameter] + string_words(argument_name))
      parameter_ids.push(parameter)
    }
    self.interface_loads = []
    self.interface_result = 0
  }
  self.argument_ids = parameter_ids
  // Every local is an OpVariable in the function's storage: keeping values in
  // memory is what lets the writer branch without building phi nodes.
  let local_ids : Map[Int32, Word] = Map([])
  for index in 0..<function.local_variables.len() {
    let local_handle = @moonnaga.Handle::new(index)
    let slot = function.local_variables.get(local_handle)
    let base = self.type_word(slot.ty)
    let pointer = self.builder.emit_typed(op_type_pointer, [
      class_function, base,
    ])
    let variable = self.builder.emit_result(op_variable, pointer, [
      class_function,
    ])
    local_ids[index] = variable
    let local_name = match slot.name {
      Some(name) => name
      None => "slot" + index.to_string()
    }
    self.builder.emit(op_name, [variable] + string_words(local_name))
  }
  self.local_ids = local_ids
  let entry : Word = self.builder.next()
  self.builder.emit(op_label, [entry])
  self.terminated = false
  self.targets = []
  for statement in function.body {
    self.statement(statement)
  }
  if !self.terminated {
    if self.interface_result != 0 {
      // The source fell off the end of an entry point that has a result; the
      // interface still needs a value, so a zero one is written.
      match function.result.ty {
        Some(ty) => {
          let value = self.builder.emit_result(
            op_constant_null,
            self.type_word(ty),
            [],
          )
          self.builder.emit(op_store, [self.interface_result, value])
        }
        None => ()
      }
      self.builder.emit(op_return, [])
    } else {
      match function.result.ty {
        Some(ty) => {
          let value = self.builder.emit_result(
            op_constant_null,
            self.type_word(ty),
            [],
          )
          self.builder.emit(op_return_value, [value])
        }
        None => self.builder.emit(op_return, [])
      }
    }
  }
  self.builder.emit(op_function_end, [])
}

///|
/// Whether this function is an entry point.
fn Writer::entry_for(self : Writer, handle : @moonnaga.Handle) -> Bool {
  for entry in self.shader.entry_points {
    if entry.function == handle {
      return true
    }
  }
  false
}

///|
/// The binding and the interpolation an entry point interface variable carries.
fn Writer::decorate_interface(
  self : Writer,
  variable : Word,
  binding : @moonnaga.Binding?,
  interpolate : @moonnaga.InterpolationBinding?,
) -> Unit {
  match binding {
    Some(@moonnaga.BuiltIn(builtin)) =>
      self.builder.emit(op_decorate, [
        variable,
        decoration_builtin,
        builtin_word(builtin),
      ])
    Some(@moonnaga.Location(location)) =>
      self.builder.emit(op_decorate, [
        variable,
        decoration_location,
        location.reinterpret_as_uint(),
      ])
    None => ()
  }
  match interpolate {
    Some(interpolation) => {
      match interpolation.interpolation {
        @moonnaga.Flat =>
          self.builder.emit(op_decorate, [variable, decoration_flat])
        @moonnaga.Linear =>
          self.builder.emit(op_decorate, [variable, decoration_no_perspective])
        @moonnaga.Perspective => ()
      }
      match interpolation.sampling {
        Some(@moonnaga.Centroid) =>
          self.builder.emit(op_decorate, [variable, decoration_centroid])
        Some(@moonnaga.Sample) =>
          self.builder.emit(op_decorate, [variable, decoration_sample])
        _ => ()
      }
    }
    None => ()
  }
}
