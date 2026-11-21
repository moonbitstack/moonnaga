// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Lowers one function, and records an entry point when its attributes name a
/// stage.
fn Builder::lower_function(self : Builder, decl : FnDecl) -> Unit raise Failed {
  let signature = match self.signatures.get(decl.name) {
    Some(signature) => signature
    None => fail("`\{decl.name}` has no signature", decl.span)
  }
  let arguments = []
  for index in 0..<decl.params.length() {
    let param = decl.params[index]
    let ty = signature.params[index]
    let argument : @moonnaga.FunctionArgument = {
      name: Some(param.name),
      ty,
      binding: self.binding_of(param.attrs),
      interpolate: self.interpolation_of(param.attrs),
    }
    arguments.push(argument)
  }
  let result : @moonnaga.FunctionResult = {
    ty: signature.result,
    binding: self.binding_of(decl.result.attrs),
    interpolate: self.interpolation_of(decl.result.attrs),
  }
  let function : @moonnaga.Function = {
    name: Some(decl.name),
    arguments,
    result,
    local_variables: @moonnaga.Arena::new(),
    expressions: @moonnaga.Arena::new(),
    named_expressions: Map([]),
    expr_types: [],
    expr_spaces: [],
    body: [],
  }
  self.shader().functions.set(signature.handle, function)
  let saved_exprs = self.exprs
  let saved_kinds = self.kinds
  let saved_locals = self.locals
  let saved_scopes = self.scopes
  let saved_return = self.return_type
  let saved_named = self.named
  self.named = []
  self.exprs = self.shader().functions.get(signature.handle).expressions
  self.kinds = []
  self.locals = @moonnaga.Arena::new()
  self.scopes = []
  self.return_type = signature.result
  self.push_scope()
  let argument_handles = []
  for index in 0..<arguments.length() {
    // A parameter of pointer type is a reference in the body: `*p` is a load.
    let kind = match self.shader().type_inner(arguments[index].ty) {
      @moonnaga.Pointer(pointer) => Reference(pointer.base, pointer.space)
      _ => Plain(arguments[index].ty)
    }
    let handle = self.emit(@moonnaga.FunctionArgument(index), kind)
    argument_handles.push(handle)
    let param_name = match arguments[index].name {
      Some(name) => name
      None => ""
    }
    self.bind(param_name, Value(handle, arguments[index].ty))
  }
  let body = []
  for stmt in decl.body {
    self.lower_stmt(stmt, body)
  }
  self.pop_scope()
  let named = self.collect_names()
  let expr_types = []
  let expr_spaces = []
  for kind in self.kinds {
    match kind {
      Plain(ty) => {
        expr_types.push(ty)
        expr_spaces.push(None)
      }
      Reference(ty, space) => {
        expr_types.push(ty)
        expr_spaces.push(Some(space))
      }
    }
  }
  let lowered = {
    ..self.shader().functions.get(signature.handle),
    local_variables: self.locals,
    expressions: self.exprs,
    named_expressions: named,
    expr_types,
    expr_spaces,
    body,
  }
  self.shader().functions.set(signature.handle, lowered)
  ignore(argument_handles)
  self.exprs = saved_exprs
  self.kinds = saved_kinds
  self.locals = saved_locals
  self.scopes = saved_scopes
  self.return_type = saved_return
  self.named = saved_named
  let stage = stage_of(decl.attrs)
  match stage {
    Some(stage) => self.add_entry_point(decl, signature.handle, stage)
    None => ()
  }
}

///|
fn stage_of(attrs : Array[Attribute]) -> @moonnaga.ShaderStage? {
  if has_attribute(attrs, "vertex") {
    Some(@moonnaga.Vertex)
  } else if has_attribute(attrs, "fragment") {
    Some(@moonnaga.Fragment)
  } else if has_attribute(attrs, "compute") {
    Some(@moonnaga.Compute)
  } else {
    None
  }
}

///|
fn Builder::add_entry_point(
  self : Builder,
  decl : FnDecl,
  function : @moonnaga.Handle,
  stage : @moonnaga.ShaderStage,
) -> Unit raise Failed {
  let size = [1, 1, 1]
  let overrides : Array[@moonnaga.Handle?] = [None, None, None]
  match find_attribute(decl.attrs, "workgroup_size") {
    Some(attr) => {
      let mut index = 0
      for arg in attr.args {
        if index < 3 {
          match arg {
            Value(expr) => {
              let value = self.const_int(expr)
              size[index] = value
            }
            Word(_, _) => ()
          }
        }
        index = index + 1
      }
    }
    None => ()
  }
  let mut early_depth_test : @moonnaga.EarlyDepthTest? = None
  match find_attribute(decl.attrs, "early_depth_test") {
    Some(attr) => {
      let word = attribute_word(attr)
      let mut conservative : @moonnaga.ConservativeDepth? = None
      if word == Some("greater_equal") {
        conservative = Some(@moonnaga.ConservativeDepth::GreaterEqual)
      } else if word == Some("less_equal") {
        conservative = Some(@moonnaga.ConservativeDepth::LessEqual)
      } else if word == Some("unchanged") {
        conservative = Some(@moonnaga.ConservativeDepth::Unchanged)
      }
      let depth_test : @moonnaga.EarlyDepthTest = { conservative, }
      early_depth_test = Some(depth_test)
    }
    None => ()
  }
  let sort_key : @moonnaga.EntryPoint = {
    name: decl.name,
    stage,
    early_depth_test,
    workgroup_size: size,
    workgroup_size_overrides: overrides,
    function,
  }
  self.shader().entry_points.push(sort_key)
  self.entry_names[decl.name] = function
  ignore(overrides)
}

///|
/// The names the source gave to expressions, which the writers use instead of a
/// generated temporary.
fn Builder::collect_names(self : Builder) -> Map[Int32, String] {
  let names : Map[Int32, String] = Map([])
  for entry in self.named {
    names[entry.0] = entry.1
  }
  names
}
