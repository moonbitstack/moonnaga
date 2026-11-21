// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn Writer::statement(
  self : Writer,
  statement : @moonnaga.Statement,
) -> Unit raise SpvError {
  if self.terminated {
    // Instructions after a branch belong to no block; a source that writes them
    // is unreachable and can be dropped.
    return
  }
  match statement {
    @moonnaga.Emit(handle) => ignore(self.expression(handle))
    @moonnaga.Block(body) =>
      for inner in body {
        self.statement(inner)
      }
    @moonnaga.If(branch) => self.if_statement(branch)
    @moonnaga.Loop(loop_statement) => self.loop_statement(loop_statement)
    @moonnaga.Switch(switch_statement) =>
      self.switch_statement(switch_statement)
    @moonnaga.Break =>
      match self.targets.length() {
        0 => unsupported("a `break` outside a loop")
        _ => {
          let target = self.targets[self.targets.length() - 1]
          self.builder.emit(op_branch, [target.break_to])
          self.terminated = true
        }
      }
    @moonnaga.Continue =>
      match self.targets.length() {
        0 => unsupported("a `continue` outside a loop")
        _ => {
          let target = self.targets[self.targets.length() - 1]
          self.builder.emit(op_branch, [target.continue_to])
          self.terminated = true
        }
      }
    @moonnaga.Return(value) => {
      if self.interface_result != 0 {
        match value {
          Some(handle) => {
            let id = self.expression(handle)
            self.builder.emit(op_store, [self.interface_result, id])
          }
          None => ()
        }
        self.builder.emit(op_return, [])
      } else {
        match value {
          Some(handle) => {
            let id = self.expression(handle)
            self.builder.emit(op_return_value, [id])
          }
          None => self.builder.emit(op_return, [])
        }
      }
      self.terminated = true
    }
    @moonnaga.Kill => {
      self.builder.emit(op_kill, [])
      self.terminated = true
    }
    @moonnaga.Store(store) => {
      let pointer = self.expression(store.pointer)
      let value = self.expression(store.value)
      self.builder.emit(op_store, [pointer, value])
    }
    @moonnaga.Call(call) => {
      let arguments = [self.function_id(call.function)]
      for argument in call.arguments {
        arguments.push(self.expression(argument))
      }
      match call.result {
        Some(result) => {
          let ty = self.expr_type(result)
          let id = self.builder.emit_result(
            op_function_call,
            self.type_word(ty),
            arguments,
          )
          self.expr_ids[result.to_int()] = id
        }
        None => self.builder.emit(op_function_call, [0] + arguments)
      }
    }
    @moonnaga.ControlBarrier(_) =>
      // Execution and memory scope are both workgroup, which is what a workgroup
      // barrier orders.
      self.builder.emit(
        op_control_barrier,
        [2, 2, 0x110], // Workgroup, Workgroup, AcquireRelease | WorkgroupMemory
      )
    @moonnaga.MemoryBarrier(kind) => {
      let semantics : Word = match kind {
        @moonnaga.Storage => 0x110
        _ => 0x110
      }
      self.builder.emit(op_memory_barrier, [2, semantics])
    }
    @moonnaga.ImageStore(_) => unsupported("`textureStore` in SPIR-V")
    @moonnaga.Atomic(_) => unsupported("an atomic_op operation in SPIR-V")
    @moonnaga.WorkGroupUniformLoad(_) =>
      unsupported("a workgroup uniform load in SPIR-V")
  }
}

///|
fn Writer::if_statement(
  self : Writer,
  branch : @moonnaga.IfStatement,
) -> Unit raise SpvError {
  let condition = self.expression(branch.condition)
  let merge = self.builder.next()
  let then_block = self.builder.next()
  let else_block = self.builder.next()
  self.builder.emit(op_selection_merge, [merge, 0])
  self.builder.emit(op_branch_conditional, [condition, then_block, else_block])
  self.builder.emit(op_label, [then_block])
  self.terminated = false
  for statement in branch.accept {
    self.statement(statement)
  }
  if !self.terminated {
    self.builder.emit(op_branch, [merge])
  }
  self.builder.emit(op_label, [else_block])
  self.terminated = false
  for statement in branch.reject {
    self.statement(statement)
  }
  if !self.terminated {
    self.builder.emit(op_branch, [merge])
  }
  self.builder.emit(op_label, [merge])
  self.terminated = false
}

///|
fn Writer::loop_statement(
  self : Writer,
  loop_statement : @moonnaga.LoopStatement,
) -> Unit raise SpvError {
  let header = self.builder.next()
  let body = self.builder.next()
  let continue_block = self.builder.next()
  let merge = self.builder.next()
  self.builder.emit(op_branch, [header])
  self.builder.emit(op_label, [header])
  self.terminated = false
  self.builder.emit(op_loop_merge, [merge, continue_block, 0])
  self.builder.emit(op_branch, [body])
  self.builder.emit(op_label, [body])
  self.terminated = false
  self.targets.push({ break_to: merge, continue_to: continue_block, })
  for statement in loop_statement.body {
    self.statement(statement)
  }
  if !self.terminated {
    self.builder.emit(op_branch, [continue_block])
  }
  self.builder.emit(op_label, [continue_block])
  self.terminated = false
  for statement in loop_statement.continuing {
    self.statement(statement)
  }
  match loop_statement.break_if {
    Some(condition) => {
      let control = self.expression(condition)
      self.builder.emit(op_branch_conditional, [control, merge, header])
    }
    None => if !self.terminated { self.builder.emit(op_branch, [header]) }
  }
  ignore(self.targets.pop())
  self.builder.emit(op_label, [merge])
  self.terminated = false
}

///|
fn Writer::switch_statement(
  self : Writer,
  switch_statement : @moonnaga.SwitchStatement,
) -> Unit raise SpvError {
  let selector = self.expression(switch_statement.selector)
  let merge = self.builder.next()
  self.builder.emit(op_selection_merge, [merge, 0])
  let labels = []
  for _ in 0..<switch_statement.cases.length() {
    labels.push(self.builder.next())
  }
  let mut default_label = merge
  let pairs = []
  for index in 0..<switch_statement.cases.length() {
    let case = switch_statement.cases[index]
    match case.value {
      @moonnaga.Default => default_label = labels[index]
      @moonnaga.I32(value) => {
        pairs.push(value.reinterpret_as_uint())
        pairs.push(labels[index])
      }
      @moonnaga.U32(value) => {
        pairs.push(value)
        pairs.push(labels[index])
      }
      @moonnaga.I64(value) => {
        pairs.push(low_word(value.reinterpret_as_uint64()))
        pairs.push(labels[index])
      }
      @moonnaga.U64(value) => {
        pairs.push(low_word(value))
        pairs.push(labels[index])
      }
    }
  }
  self.builder.emit(op_switch, [selector, default_label] + pairs)
  for index in 0..<switch_statement.cases.length() {
    self.builder.emit(op_label, [labels[index]])
    self.terminated = false
    for statement in switch_statement.cases[index].body {
      self.statement(statement)
    }
    if !self.terminated {
      self.builder.emit(op_branch, [merge])
    }
  }
  self.builder.emit(op_label, [merge])
  self.terminated = false
}
