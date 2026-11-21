// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What an expression means once its type is known: either a value of that type,
/// or a pointer to one. WGSL hides the difference; the intermediate
/// representation does not, because a store needs the pointer and a load needs
/// the value.
#derive(Debug)
pub(all) enum Resolved {
  Plain(@moonnaga.Handle)
  Reference(@moonnaga.Handle, @moonnaga.AddressSpace)
}

///|
/// A value the front end has already worked out, kept so that array lengths,
/// `case` labels and `const_assert` can be settled before the module is built.
#derive(Debug)
pub(all) enum ConstValue {
  Int(Int64)
  Float(Double)
  Bool(Bool)
  Vector(Array[ConstValue])
  Aggregate(Array[ConstValue])
}

///|
/// What a name refers to inside a function or at module scope.
#derive(Debug)
pub(all) enum Binding {
  /// An expression that is already a value, such as a `let` or a constant.
  Value(@moonnaga.Handle, @moonnaga.Handle)
  /// A local variable: a pointer in the function address space.
  Local(@moonnaga.Handle, @moonnaga.Handle)
  /// A module-scope variable, which is a pointer in its own address space.
  Global(@moonnaga.Handle, @moonnaga.Handle, @moonnaga.AddressSpace)
  /// A module-scope constant.
  Constant(@moonnaga.Handle, @moonnaga.Handle)
  /// A pipeline-overridable constant.
  Override(@moonnaga.Handle, @moonnaga.Handle)
}

///|
#derive(Debug)
pub(all) struct FnSignature {
  handle : @moonnaga.Handle
  params : Array[@moonnaga.Handle]
  result : @moonnaga.Handle?
}

///|
#derive(Debug)
pub(all) struct ConstEntry {
  handle : @moonnaga.Handle
  ty : @moonnaga.Handle
  value : ConstValue?
}

///|
/// Builds a module out of a parsed translation unit.
pub(all) struct Builder {
  types : TypeTable
  globals : Map[String, @moonnaga.Handle]
  consts : Map[String, ConstEntry]
  override_names : Map[String, @moonnaga.Handle]
  signatures : Map[String, FnSignature]
  entry_names : Map[String, @moonnaga.Handle]
  // The arenas and the scope stack belong to whichever function is being
  // lowered; module-level initialisers use them too, before any function does.
  mut exprs : @moonnaga.Arena[@moonnaga.Expression]
  mut kinds : Array[Resolved]
  mut locals : @moonnaga.Arena[@moonnaga.LocalVariable]
  mut scopes : Array[Map[String, Binding]]
  mut return_type : @moonnaga.Handle?
  /// The function whose body is being lowered, for the name of a temporary.
  mut current_function : @moonnaga.Handle?
  /// The names the source gave to expressions of the current function.
  mut named : Array[(Int32, String)]
  /// The statement list a call appends its `@moonnaga.Call` statement to as the
  /// expression is lowered.
  mut emits : Array[@moonnaga.Statement]
}

///|
pub fn Builder::new() -> Builder {
  {
    types: TypeTable::new(),
    globals: Map([]),
    consts: Map([]),
    override_names: Map([]),
    signatures: Map([]),
    entry_names: Map([]),
    exprs: @moonnaga.Arena::new(),
    kinds: [],
    locals: @moonnaga.Arena::new(),
    scopes: [],
    return_type: None,
    current_function: None,
    named: [],
    emits: [],
  }
}

///|
pub fn Builder::shader(self : Builder) -> @moonnaga.Module {
  self.types.shader
}

///|
fn Builder::emit(
  self : Builder,
  expr : @moonnaga.Expression,
  resolved : Resolved,
) -> @moonnaga.Handle {
  let handle = self.exprs.add(expr)
  while self.kinds.length() < self.exprs.len() {
    self.kinds.push(resolved)
  }
  self.kinds[handle.to_int()] = resolved
  handle
}

///|
pub fn Builder::kind_of(self : Builder, handle : @moonnaga.Handle) -> Resolved {
  self.kinds[handle.to_int()]
}

///|
fn Builder::type_of(
  self : Builder,
  handle : @moonnaga.Handle,
) -> @moonnaga.Handle {
  match self.kind_of(handle) {
    Plain(ty) => ty
    Reference(ty, _) => ty
  }
}

///|
/// The expression's value, with a load inserted when it is a pointer.
fn Builder::as_value(
  self : Builder,
  handle : @moonnaga.Handle,
) -> @moonnaga.Handle {
  match self.kind_of(handle) {
    Plain(_) => handle
    Reference(ty, _) => self.emit(@moonnaga.Load(handle), Plain(ty))
  }
}

///|
/// The pointer an expression denotes, which a store needs.
fn Builder::as_reference(
  self : Builder,
  handle : @moonnaga.Handle,
) -> @moonnaga.Handle raise Failed {
  match self.kind_of(handle) {
    Reference(_, _) => handle
    Plain(_) =>
      fail("this expression is not assignable", @moonnaga.Span::new(0, 0))
  }
}

///|
fn Builder::push_scope(self : Builder) -> Unit {
  self.scopes.push(Map([]))
}

///|
fn Builder::pop_scope(self : Builder) -> Unit {
  ignore(self.scopes.pop())
}

///|
fn Builder::bind(self : Builder, name : String, binding : Binding) -> Unit {
  let index = self.scopes.length() - 1
  self.scopes[index][name] = binding
}

///|
fn Builder::lookup(self : Builder, name : String) -> Binding? {
  let mut index = self.scopes.length() - 1
  while index >= 0 {
    match self.scopes[index].get(name) {
      Some(binding) => return Some(binding)
      None => index = index - 1
    }
  }
  None
}

///|
/// Turns a translation unit into a module.
pub fn build(unit : TranslationUnit) -> @moonnaga.Module raise Failed {
  let builder = Builder::new()
  // Constants and types first: a struct's array length may name a constant, and
  // a global's type may name a struct.
  for decl in unit.decls {
    match decl {
      Const(constant) => builder.declare_const(constant)
      Override(over) => builder.declare_override(over)
      Struct(structure) => builder.declare_struct(structure)
      Alias(name, target, _) => {
        let handle = builder.resolve_type(target)
        builder.types.bind_name(name, handle)
      }
      _ => ()
    }
  }
  // Then the signatures, so a function may call one declared after it, which
  // WGSL allows.
  for decl in unit.decls {
    match decl {
      Fn(function) => builder.declare_signature(function)
      _ => ()
    }
  }
  // Globals first: a function body may read one declared after it.
  for decl in unit.decls {
    match decl {
      Var(variable) => builder.declare_global(variable)
      _ => ()
    }
  }
  for decl in unit.decls {
    match decl {
      Fn(function) => builder.lower_function(function)
      Var(_) => ()
      ConstAssert(expr, span) => builder.check_const_assert(expr, span)
      Enable(_) | Requires(_) | Diagnostic(_, _) => ()
      Const(_) | Override(_) | Struct(_) | Alias(_, _, _) => ()
    }
  }
  builder.shader()
}
