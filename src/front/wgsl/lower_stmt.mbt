// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Lowers a list of statements into the statement list it appends to.
fn Builder::lower_into(
  self : Builder,
  stmts : Array[Stmt],
  out : Array[@moonnaga.Statement],
) -> Unit raise Failed {
  self.push_scope()
  for stmt in stmts {
    self.lower_stmt(stmt, out)
  }
  self.pop_scope()
}

///|
fn Builder::lower_stmt(
  self : Builder,
  stmt : Stmt,
  out : Array[@moonnaga.Statement],
) -> Unit raise Failed {
  self.emits = out
  match stmt {
    SEmpty => ()
    SExpr(expr) => {
      let handle = self.lower_expr(expr)
      out.push(@moonnaga.Emit(handle))
    }
    SAssign(target, op, value, span) =>
      self.lower_assign(target, op, value, span, out)
    SIncrement(target, delta, span) => {
      let one = self.emit(
        @moonnaga.Literal(@moonnaga.I32(1)),
        Plain(self.types.scalar_type(@moonnaga.scalar_i32)),
      )
      let op = if delta > 0 { AssignOp::Add } else { AssignOp::Subtract }
      self.lower_assign_with(target, op, one, span, out)
    }
    SLet(name, ty, init, _, _) => self.lower_let(name, ty, init)
    SVar(name, ty, init, _, space, span) =>
      self.lower_local_var(name, ty, init, space, span, out)
    SConst(name, ty, init, _) => self.lower_local_const(name, ty, init)
    SIf(condition, accept, reject) => {
      let guard_value = self.lower_value(condition)
      let accept_out = []
      self.lower_into(accept, accept_out)
      let reject_out = []
      self.lower_into(reject, reject_out)
      out.push(
        @moonnaga.If({
          condition: guard_value,
          accept: accept_out,
          reject: reject_out,
        }),
      )
    }
    SLoop(body, continuing, break_if) => {
      let body_out = []
      self.lower_into(body, body_out)
      let continuing_out = []
      self.lower_into(continuing, continuing_out)
      let guard_value = match break_if {
        Some(expr) => Some(self.lower_value(expr))
        None => None
      }
      out.push(
        @moonnaga.Loop({
          body: body_out,
          continuing: continuing_out,
          break_if: guard_value,
        }),
      )
    }
    SFor(parts) => self.lower_for(parts, out)
    SWhile(condition, body) => {
      let body_out = []
      self.lower_into(body, body_out)
      let guard_value = self.lower_value(condition)
      let negated = self.emit(
        @moonnaga.Unary({ op: @moonnaga.LogicalNot, expr: guard_value, }),
        Plain(self.types.scalar_type(@moonnaga.boolean())),
      )
      // `while` is a loop whose first act is to leave when the condition fails.
      let guarded = [
        @moonnaga.If({
          condition: negated,
          accept: [@moonnaga.Break],
          reject: [],
        }),
      ]
      guarded.append(body_out)
      out.push(
        @moonnaga.Loop({ body: guarded, continuing: [], break_if: None, }),
      )
    }
    SSwitch(selector, arms) => self.lower_switch(selector, arms, out)
    SBreak(_) => out.push(@moonnaga.Break)
    SContinue(_) => out.push(@moonnaga.Continue)
    SReturn(value) => {
      let lowered = match value {
        Some(expr) => {
          let handle = self.lower_value(expr)
          match self.return_type {
            Some(ty) => self.coerce(handle, ty)
            None => ()
          }
          Some(handle)
        }
        None => None
      }
      out.push(@moonnaga.Return(lowered))
    }
    SDiscard(_) => out.push(@moonnaga.Kill)
    SBlock(stmts) => {
      let inner = []
      self.lower_into(stmts, inner)
      out.push(@moonnaga.Block(inner))
    }
    SConstAssert(expr, span) => self.check_const_assert(expr, span)
  }
}

///|
fn Builder::lower_for(
  self : Builder,
  parts : ForParts,
  out : Array[@moonnaga.Statement],
) -> Unit raise Failed {
  match parts.init {
    Some(stmt) => self.lower_stmt(stmt, out)
    None => ()
  }
  let body_out = []
  self.push_scope()
  match parts.condition {
    Some(condition) => {
      let guard_value = self.lower_value(condition)
      let negated = self.emit(
        @moonnaga.Unary({ op: @moonnaga.LogicalNot, expr: guard_value, }),
        Plain(self.types.scalar_type(@moonnaga.boolean())),
      )
      body_out.push(
        @moonnaga.If({
          condition: negated,
          accept: [@moonnaga.Break],
          reject: [],
        }),
      )
    }
    None => ()
  }
  for stmt in parts.body {
    self.lower_stmt(stmt, body_out)
  }
  self.pop_scope()
  let continuing = []
  match parts.update {
    Some(stmt) => self.lower_stmt(stmt, continuing)
    None => ()
  }
  out.push(@moonnaga.Loop({ body: body_out, continuing, break_if: None, }))
}

///|
fn Builder::lower_switch(
  self : Builder,
  selector : Expr,
  arms : Array[SwitchArm],
  out : Array[@moonnaga.Statement],
) -> Unit raise Failed {
  let value = self.lower_value(selector)
  let selector_ty = self.type_of(value)
  let cases = []
  for arm in arms {
    let case_value = match arm.value {
      Some(expr) => {
        let lowered = self.lower_value(expr)
        self.coerce(lowered, selector_ty)
        self.switch_value(lowered)
      }
      None => @moonnaga.Default
    }
    let body = []
    self.lower_into(arm.body, body)
    let fall_through = !ends_with_break(body)
    let switch_case : @moonnaga.SwitchCase = {
      value: case_value,
      body,
      fall_through,
    }
    cases.push(switch_case)
  }
  out.push(@moonnaga.Switch({ selector: value, cases, }))
}

///|
fn Builder::switch_value(
  self : Builder,
  handle : @moonnaga.Handle,
) -> @moonnaga.SwitchValue raise Failed {
  match self.fold(handle) {
    Some(Int(value)) =>
      match self.shader().type_inner(self.type_of(handle)) {
        Scalar(scalar) =>
          match scalar.kind {
            Sint => @moonnaga.I32(value.to_int())
            Uint => @moonnaga.U32(value.to_uint())
            _ => @moonnaga.I32(value.to_int())
          }
        _ => @moonnaga.I32(value.to_int())
      }
    _ =>
      match self.exprs.get(handle) {
        @moonnaga.Literal(@moonnaga.I32(value)) => @moonnaga.I32(value)
        @moonnaga.Literal(@moonnaga.U32(value)) => @moonnaga.U32(value)
        @moonnaga.Literal(@moonnaga.AbstractInt(value)) =>
          @moonnaga.I32(value.to_int())
        _ => fail("a `case` needs a constant", @moonnaga.Span::new(0, 0))
      }
  }
}

///|
/// Whether a case body ends in a jump, which is what decides whether the switch
/// needs a `break` after it.
fn ends_with_break(body : Array[@moonnaga.Statement]) -> Bool {
  if body.is_empty() {
    return false
  }
  match body[body.length() - 1] {
    @moonnaga.Break
    | @moonnaga.Continue
    | @moonnaga.Return(_)
    | @moonnaga.Kill => true
    _ => false
  }
}

///|
fn Builder::lower_assign(
  self : Builder,
  target : Expr,
  op : AssignOp,
  value : Expr,
  span : @moonnaga.Span,
  out : Array[@moonnaga.Statement],
) -> Unit raise Failed {
  let handle = self.lower_expr(value)
  self.lower_assign_with(target, op, handle, span, out)
}

///|
fn Builder::lower_assign_with(
  self : Builder,
  target : Expr,
  op : AssignOp,
  value : @moonnaga.Handle,
  _span : @moonnaga.Span,
  out : Array[@moonnaga.Statement],
) -> Unit raise Failed {
  // `_ = expr;` evaluates the expression and throws the value away.
  match target {
    Ident("_", _) => {
      ignore(self.as_value(value))
      ()
    }
    _ => {
      let reference = self.as_reference(self.lower_expr(target))
      let pointee = self.type_of(reference)
      self.coerce(value, pointee)
      let stored = if op == AssignOp::Assign {
        value
      } else {
        let current = self.as_value(reference)
        let operator = match op {
          Add => @moonnaga.BinaryOperator::Add
          Subtract => @moonnaga.BinaryOperator::Subtract
          Multiply => @moonnaga.BinaryOperator::Multiply
          Divide => @moonnaga.BinaryOperator::Divide
          Modulo => @moonnaga.BinaryOperator::Modulo
          And => @moonnaga.BinaryOperator::And
          Or => @moonnaga.BinaryOperator::InclusiveOr
          Xor => @moonnaga.BinaryOperator::ExclusiveOr
          ShiftLeft => @moonnaga.BinaryOperator::ShiftLeft
          ShiftRight => @moonnaga.BinaryOperator::ShiftRight
          Assign => @moonnaga.BinaryOperator::Add
        }
        self.emit(
          @moonnaga.Binary({ op: operator, left: current, right: value, }),
          Plain(pointee),
        )
      }
      out.push(@moonnaga.Store({ pointer: reference, value: stored, }))
    }
  }
}

///|
fn Builder::lower_let(
  self : Builder,
  name : String,
  ty : TypeExpr?,
  init : Expr?,
) -> Unit raise Failed {
  let handle = match init {
    Some(expr) => self.lower_expr(expr)
    None => fail("a `let` needs an initialiser", @moonnaga.Span::new(0, 0))
  }
  let bound_ty = match ty {
    Some(annotation) => {
      let target = self.resolve_type(annotation)
      self.coerce(handle, target)
      target
    }
    None =>
      match self.kind_of(handle) {
        // A `let` bound to a pointer stays a pointer; that is how `let p = &x`
        // becomes something an assignment can dereference.
        Reference(base, space) => self.types.pointer_type(base, space)
        Plain(inner) => self.concretize(inner)
      }
  }
  self.name_expression(handle, name)
  self.bind(name, Value(handle, bound_ty))
  // A named expression needs a statement of its own, because the writer prints
  // it as a `let` rather than inlining it at every use.
  self.emits.push(@moonnaga.Emit(handle))
}

///|
/// Records that the source calls this expression something, so a writer prints
/// the name instead of the expression tree.
fn Builder::name_expression(
  self : Builder,
  handle : @moonnaga.Handle,
  name : String,
) -> Unit {
  let interesting = match self.exprs.get(handle) {
    @moonnaga.Literal(_)
    | @moonnaga.ZeroValue(_)
    | @moonnaga.Constant(_)
    | @moonnaga.FunctionArgument(_)
    | @moonnaga.GlobalVariable(_)
    | @moonnaga.LocalVariable(_) => false
    _ => true
  }
  if interesting {
    self.named.push((handle.to_int(), name))
  }
}

///|
fn Builder::lower_local_var(
  self : Builder,
  name : String,
  ty : TypeExpr?,
  init : Expr?,
  space : String?,
  span : @moonnaga.Span,
  out : Array[@moonnaga.Statement],
) -> Unit raise Failed {
  let declared = match ty {
    Some(annotation) => self.resolve_type(annotation)
    None =>
      match init {
        Some(expr) => {
          let handle = self.lower_value(expr)
          self.concretize(self.type_of(handle))
        }
        None => fail("a `var` needs a type or an initialiser", span)
      }
  }
  let variable = self.locals.add({ name: Some(name), ty: declared, init: None, })
  self.bind(name, Local(variable, declared))
  match init {
    Some(expr) => {
      let value = self.lower_value(expr)
      self.coerce(value, declared)
      let reference = self.emit(
        @moonnaga.LocalVariable(variable),
        Reference(declared, @moonnaga.Function),
      )
      out.push(@moonnaga.Store({ pointer: reference, value, }))
    }
    None => ()
  }
  ignore(space)
}

///|
fn Builder::lower_local_const(
  self : Builder,
  name : String,
  ty : TypeExpr?,
  init : Expr,
) -> Unit raise Failed {
  let handle = self.lower_value(init)
  let bound_ty = match ty {
    Some(annotation) => {
      let target = self.resolve_type(annotation)
      self.coerce(handle, target)
      target
    }
    None => self.concretize(self.type_of(handle))
  }
  // A local constant lives in the function, so it is a name bound to the value
  // rather than an entry of the module's constants; an array length that names
  // it folds that value like any other.
  self.bind(name, Value(handle, bound_ty))
}
