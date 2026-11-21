// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn Writer::write_functions(self : Writer) -> Unit {
  let entry_points = self.entry_function_set()
  for index in 0..<self.shader.functions.len() {
    let handle = @moonnaga.Handle::new(index)
    if entry_points.contains(index) {
      continue
    }
    let function = self.shader.functions.get(handle)
    self.write_function(function, None, [])
    self.blank()
  }
}

///|
fn Writer::write_entry_points(self : Writer) -> Unit {
  for entry in self.shader.entry_points {
    let function = self.shader.functions.get(entry.function)
    let attributes = [stage_text(entry.stage)]
    if entry.stage == @moonnaga.Compute {
      let size = [
        entry.workgroup_size[0].to_string(),
        entry.workgroup_size[1].to_string(),
        entry.workgroup_size[2].to_string(),
      ]
      attributes.push("@workgroup_size(" + join_with(size, ", ") + ")")
    }
    match entry.early_depth_test {
      Some(depth_test) => {
        let text = match depth_test.conservative {
          Some(@moonnaga.GreaterEqual) => "@early_depth_test(greater_equal)"
          Some(@moonnaga.LessEqual) => "@early_depth_test(less_equal)"
          Some(@moonnaga.Unchanged) => "@early_depth_test(unchanged)"
          None => "@early_depth_test"
        }
        attributes.push(text)
      }
      None => ()
    }
    self.write_function(function, Some(entry), attributes)
    self.blank()
  }
}

///|
fn stage_text(stage : @moonnaga.ShaderStage) -> String {
  match stage {
    @moonnaga.Vertex => "@vertex"
    @moonnaga.Fragment => "@fragment"
    @moonnaga.Compute => "@compute"
    @moonnaga.Task => "@task"
    @moonnaga.Mesh => "@mesh"
  }
}

///|
fn Writer::entry_function_set(self : Writer) -> Map[Int32, Bool] {
  let set = Map([])
  for entry in self.shader.entry_points {
    set[entry.function.to_int()] = true
  }
  set
}

///|
fn Writer::write_function(
  self : Writer,
  function : @moonnaga.Function,
  entry : @moonnaga.EntryPoint?,
  attributes : Array[String],
) -> Unit {
  self.local_names = Map([])
  self.expr_names = Map([])
  self.written = Map([])
  self.temps = 0
  self.argument_names = []
  let function_handle = self.find_function(function)
  let name = self.function_name(function_handle)
  // Names first: an argument's name may already be taken by a local, and the
  // other way round.
  // Locals and arguments live in the function's own scope, but they may not
  // shadow a module-scope name, so they take a namer that has those reserved.
  let local_namer = self.local_namer()
  let parameters = []
  for index in 0..<function.arguments.length() {
    let argument = function.arguments[index]
    let base = match argument.name {
      Some(name) => name
      None => "arg" + index.to_string()
    }
    let argument_name = local_namer.unique(base)
    self.argument_names.push(argument_name)
    let attributes = self.binding_text(argument.binding, argument.interpolate)
    let separator = if attributes.is_empty() { "" } else { " " }
    parameters.push(
      attributes +
      separator +
      argument_name +
      ": " +
      self.type_text(argument.ty),
    )
  }
  function.local_variables.each(fn(handle, slot) {
    let base = match slot.name {
      Some(name) => name
      None => "var" + handle.to_int().to_string()
    }
    self.local_names[handle.to_int()] = local_namer.unique(base)
  })
  for entry in function.named_expressions {
    self.expr_names[entry.0] = local_namer.unique(entry.1)
  }
  let mut result = ""
  match function.result.ty {
    Some(ty) => {
      let attributes = self.binding_text(
        function.result.binding,
        function.result.interpolate,
      )
      let separator = if attributes.is_empty() { "" } else { " " }
      result = " -> " + attributes + separator + self.type_text(ty)
    }
    None => ()
  }
  if !attributes.is_empty() {
    self.line(join_with(attributes, " ") + " ")
  }
  self.line(
    "fn " + name + "(" + join_with(parameters, ", ") + ")" + result + " {",
  )
  self.indent = self.indent + 1
  let frame : Frame = { function, }
  self.write_locals(function)
  self.write_body(frame, function.body)
  if !ends_in_jump(function.body) {
    self.line("return;")
  }
  self.indent = self.indent - 1
  self.line("}")
  ignore(entry)
}

///|
fn Writer::find_function(
  self : Writer,
  function : @moonnaga.Function,
) -> @moonnaga.Handle {
  for index in 0..<self.shader.functions.len() {
    let candidate = self.shader.functions.get(@moonnaga.Handle::new(index))
    if candidate.name == function.name &&
      candidate.body.length() == function.body.length() {
      return @moonnaga.Handle::new(index)
    }
  }
  { index: 0, }
}

///|
fn Writer::write_locals(self : Writer, function : @moonnaga.Function) -> Unit {
  function.local_variables.each(fn(handle, slot) {
    let name = self.local_name(handle)
    self.line("var " + name + ": " + self.type_text(slot.ty) + ";")
  })
}

///|
fn Writer::write_body(
  self : Writer,
  frame : Frame,
  body : Array[@moonnaga.Statement],
) -> Unit {
  for statement in body {
    self.write_statement(frame, statement)
  }
}

///|
fn Writer::write_statement(
  self : Writer,
  frame : Frame,
  statement : @moonnaga.Statement,
) -> Unit {
  match statement {
    @moonnaga.Emit(handle) => self.write_emit(frame, handle)
    @moonnaga.Block(body) => self.write_body(frame, body)
    @moonnaga.If(branch) => {
      let condition = self.expr_text(frame, branch.condition)
      self.line("if " + parenthesized(condition) + " {")
      self.indent = self.indent + 1
      self.write_body(frame, branch.accept)
      self.indent = self.indent - 1
      if branch.reject.is_empty() {
        self.line("}")
      } else {
        self.line("} else {")
        self.indent = self.indent + 1
        self.write_body(frame, branch.reject)
        self.indent = self.indent - 1
        self.line("}")
      }
    }
    @moonnaga.Switch(switch_statement) => {
      let selector = self.expr_text(frame, switch_statement.selector)
      self.line("switch " + selector + " {")
      self.indent = self.indent + 1
      for case in switch_statement.cases {
        let label = match case.value {
          @moonnaga.I32(value) => value.to_string()
          @moonnaga.U32(value) => value.to_string() + "u"
          @moonnaga.I64(value) => value.to_string()
          @moonnaga.U64(value) => value.to_string()
          @moonnaga.Default => "default"
        }
        self.line("case " + label + ": {")
        self.indent = self.indent + 1
        self.write_body(frame, case.body)
        self.indent = self.indent - 1
        self.line("}")
      }
      self.indent = self.indent - 1
      self.line("}")
    }
    @moonnaga.Loop(loop_statement) => {
      self.line("loop {")
      self.indent = self.indent + 1
      self.write_body(frame, loop_statement.body)
      if !loop_statement.continuing.is_empty() {
        self.line("continuing {")
        self.indent = self.indent + 1
        self.write_body(frame, loop_statement.continuing)
        self.indent = self.indent - 1
        self.line("}")
      }
      match loop_statement.break_if {
        Some(condition) => {
          let text = self.expr_text(frame, condition)
          self.line("break if " + text + ";")
        }
        None => ()
      }
      self.indent = self.indent - 1
      self.line("}")
    }
    @moonnaga.Break => self.line("break;")
    @moonnaga.Continue => self.line("continue;")
    @moonnaga.Return(value) => {
      let text = match value {
        Some(handle) => " " + self.expr_text(frame, handle) + ";"
        None => ";"
      }
      self.line("return" + text)
    }
    @moonnaga.Kill => self.line("discard;")
    @moonnaga.ControlBarrier(_) => self.line("workgroupBarrier();")
    @moonnaga.MemoryBarrier(kind) =>
      match kind {
        @moonnaga.Storage => self.line("storageBarrier();")
        _ => self.line("textureBarrier();")
      }
    @moonnaga.Store(store) => {
      let value = self.expr_text(frame, store.value)
      let place = self.place_text(frame, store.pointer)
      self.line(place + " = " + value + ";")
    }
    @moonnaga.ImageStore(store) => {
      let parts = [
        self.expr_text(frame, store.image),
        self.expr_text(frame, store.coordinate),
        self.expr_text(frame, store.value),
      ]
      match store.array_index {
        Some(index) => parts.insert(2, self.expr_text(frame, index))
        None => ()
      }
      self.line("textureStore(" + join_with(parts, ", ") + ");")
    }
    @moonnaga.Atomic(atomic_op) => {
      let name = atomic_name(atomic_op.fun)
      let text = name +
        "(" +
        self.place_text(frame, atomic_op.pointer) +
        ", " +
        self.expr_text(frame, atomic_op.value) +
        ")"
      let result_name = self.temp()
      self.expr_names[atomic_op.result.to_int()] = result_name
      self.line("let " + result_name + " = " + text + ";")
    }
    @moonnaga.WorkGroupUniformLoad(load) => {
      let result_name = self.temp()
      self.expr_names[load.result.to_int()] = result_name
      self.line(
        "let " +
        result_name +
        " = workgroupUniformLoad(" +
        self.place_text(frame, load.pointer) +
        ");",
      )
    }
    @moonnaga.Call(call) => {
      let arguments = []
      for argument in call.arguments {
        arguments.push(self.expr_text(frame, argument))
      }
      let text = self.function_name(call.function) +
        "(" +
        join_with(arguments, ", ") +
        ")"
      match call.result {
        Some(result) => {
          let result_name = self.temp()
          self.expr_names[result.to_int()] = result_name
          self.written[result.to_int()] = true
          self.line("let " + result_name + " = " + text + ";")
        }
        None => self.line(text + ";")
      }
    }
  }
}

///|
fn atomic_name(fun : @moonnaga.AtomicFunction) -> String {
  match fun {
    @moonnaga.AtomicAdd => "atomicAdd"
    @moonnaga.AtomicSubtract => "atomicSub"
    @moonnaga.AtomicAnd => "atomicAnd"
    @moonnaga.AtomicExclusiveOr => "atomicXor"
    @moonnaga.AtomicInclusiveOr => "atomicOr"
    @moonnaga.AtomicMin => "atomicMin"
    @moonnaga.AtomicMax => "atomicMax"
    @moonnaga.AtomicExchange => "atomicExchange"
    @moonnaga.AtomicCompareExchangeWeak => "atomicCompareExchangeWeak"
  }
}

///|
/// Writes one expression of the statement stream.
///
/// An expression the source named becomes a `let` under that name; an expensive
/// one gets a temporary so later statements can refer to it; a pure one that
/// something else will inline is dropped.
fn Writer::write_emit(
  self : Writer,
  frame : Frame,
  handle : @moonnaga.Handle,
) -> Unit {
  match self.written.get(handle.to_int()) {
    Some(_) => return
    None => ()
  }
  match self.expr_names.get(handle.to_int()) {
    Some(name) => {
      let text = self.expr_text_unrecorded(frame, handle)
      self.line("let " + name + " = " + text + ";")
      self.written[handle.to_int()] = true
    }
    None =>
      match frame.function.expressions.get(handle) {
        @moonnaga.Math(_)
        | @moonnaga.ImageSample(_)
        | @moonnaga.ImageLoad(_)
        | @moonnaga.ImageQuery(_)
        | @moonnaga.Relational(_)
        | @moonnaga.Derivative(_)
        | @moonnaga.ArrayLength(_) => {
          let name = self.temp()
          let text = self.expr_text_unrecorded(frame, handle)
          self.expr_names[handle.to_int()] = name
          self.written[handle.to_int()] = true
          self.line("let " + name + " = " + text + ";")
        }
        _ => ()
      }
  }
}

///|
/// The text of an expression whose name is about to be declared, written without
/// looking its own name up again.
fn Writer::expr_text_unrecorded(
  self : Writer,
  frame : Frame,
  handle : @moonnaga.Handle,
) -> String {
  let name = self.expr_names.get(handle.to_int())
  self.expr_names.remove(handle.to_int().to_int())
  let text = self.expr_text(frame, handle)
  match name {
    Some(name) => self.expr_names[handle.to_int()] = name
    None => ()
  }
  text
}

///|
/// Whether the last statement of a body leaves the function or the loop, which
/// decides whether the writer has to add a closing `return;`.
fn ends_in_jump(body : Array[@moonnaga.Statement]) -> Bool {
  if body.is_empty() {
    return false
  }
  match body[body.length() - 1] {
    @moonnaga.Return(_)
    | @moonnaga.Kill
    | @moonnaga.Break
    | @moonnaga.Continue => true
    _ => false
  }
}

///|
/// A condition as the grammar wants it: parenthesized, but not twice when the
/// expression already wrote its own pair.
fn parenthesized(text : String) -> String {
  if text.has_prefix("(") && text.has_suffix(")") {
    text
  } else {
    "(" + text + ")"
  }
}
