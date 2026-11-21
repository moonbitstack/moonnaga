// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn find_attribute(attrs : Array[Attribute], name : String) -> Attribute? {
  for attr in attrs {
    if attr.name == name {
      return Some(attr)
    }
  }
  None
}

///|
fn has_attribute(attrs : Array[Attribute], name : String) -> Bool {
  match find_attribute(attrs, name) {
    Some(_) => true
    None => false
  }
}

///|
/// The first argument of an attribute as a word, for `@interpolate(flat)` and
/// friends.
fn attribute_word(attr : Attribute) -> String? {
  for arg in attr.args {
    match arg {
      Word(word, _) => return Some(word)
      Value(_) => ()
    }
  }
  None
}

///|
fn Builder::declare_const(
  self : Builder,
  decl : ConstDecl,
) -> Unit raise Failed {
  let saved = self.begin_module_scope()
  let init = self.lower_const_expr(decl.init)
  let ty = match decl.ty {
    Some(annotated) => {
      let wanted = self.resolve_type(annotated)
      self.coerce(init, wanted)
      wanted
    }
    None => self.concretize(self.type_of(init))
  }
  let value = self.fold(init)
  let handle = self.shader().constants.add({ name: Some(decl.name), ty, init, })
  self.consts[decl.name] = { handle, ty, value, }
  self.end_module_scope(saved)
}

///|
fn Builder::declare_override(
  self : Builder,
  decl : OverrideDecl,
) -> Unit raise Failed {
  let saved = self.begin_module_scope()
  let init = match decl.init {
    Some(expr) => Some(self.lower_const_expr(expr))
    None => None
  }
  let ty = match decl.ty {
    Some(annotated) => self.resolve_type(annotated)
    None =>
      match init {
        Some(handle) => self.concretize(self.type_of(handle))
        None => fail("an override needs a type or an initialiser", decl.span)
      }
  }
  match init {
    Some(handle) => self.coerce(handle, ty)
    None => ()
  }
  let derived_init = match init {
    Some(_) => init
    None => Some(self.zero_value(ty))
  }
  let handle = self.shader().overrides.add({
    name: decl.name,
    ty,
    init: derived_init,
  })
  self.override_names[decl.name] = handle
  self.end_module_scope(saved)
}

///|
/// An initialiser at module scope lives in the module's own expression arena
/// rather than in a function's.
fn Builder::begin_module_scope(
  self : Builder,
) -> (Array[@moonnaga.Expression], Array[Resolved]) {
  let saved_exprs = self.exprs
  let saved_kinds = self.kinds
  self.exprs = self.shader().const_expressions
  self.kinds = []
  (saved_exprs.items, saved_kinds)
}

///|
fn Builder::end_module_scope(
  self : Builder,
  saved : (Array[@moonnaga.Expression], Array[Resolved]),
) -> Unit {
  let (exprs, kinds) = saved
  self.exprs = { items: exprs, }
  self.kinds = kinds
}

///|
fn Builder::declare_struct(
  self : Builder,
  decl : StructDecl,
) -> Unit raise Failed {
  let members = []
  for field in decl.fields {
    let ty = match field.ty {
      Some(expr) => self.resolve_type(expr)
      None => fail("a struct field needs a type", field.span)
    }
    let binding = self.binding_of(field.attrs)
    let interpolate = self.interpolation_of(field.attrs)
    let field : @moonnaga.StructMember = {
      name: field.name,
      ty,
      binding,
      offset: 0,
      interpolate,
    }
    members.push(field)
  }
  ignore(self.types.struct_type(decl.name, members))
}

///|
/// The binding an attribute list gives a member or an entry point argument.
fn Builder::binding_of(
  self : Builder,
  attrs : Array[Attribute],
) -> @moonnaga.Binding? raise Failed {
  match find_attribute(attrs, "builtin") {
    Some(attr) =>
      match attribute_word(attr) {
        Some(word) =>
          Some(@moonnaga.Binding::BuiltIn(builtin_of(word, attr.span)))
        None => fail("`@builtin` needs a name", attr.span)
      }
    None =>
      match find_attribute(attrs, "location") {
        Some(attr) =>
          Some(@moonnaga.Binding::Location(self.attribute_index(attr)))
        None => None
      }
  }
}

///|
fn Builder::interpolation_of(
  _self : Builder,
  attrs : Array[Attribute],
) -> @moonnaga.InterpolationBinding? raise Failed {
  match find_attribute(attrs, "interpolate") {
    None => None
    Some(attr) => {
      let words = []
      for arg in attr.args {
        match arg {
          Word(word, _) => words.push(word)
          Value(_) => ()
        }
      }
      if words.is_empty() {
        return fail("`@interpolate` needs a mode", attr.span)
      }
      let interpolation = match words[0] {
        "perspective" => @moonnaga.Perspective
        "linear" => @moonnaga.Linear
        "flat" => @moonnaga.Flat
        other => fail("`\{other}` is not an interpolation mode", attr.span)
      }
      let sampling = if words.length() > 1 {
        match words[1] {
          "center" => Some(@moonnaga.Center)
          "centroid" => Some(@moonnaga.Centroid)
          "sample" => Some(@moonnaga.Sample)
          "first" => Some(@moonnaga.First)
          "either" => Some(@moonnaga.Either)
          other => fail("`\{other}` is not a sampling mode", attr.span)
        }
      } else {
        None
      }
      Some({ interpolation, sampling, })
    }
  }
}

///|
fn Builder::attribute_index(
  _self : Builder,
  attr : Attribute,
) -> Int32 raise Failed {
  for arg in attr.args {
    match arg {
      Value(Number(number, _)) => return int_of_number(number, attr.span)
      Value(_) => fail("expected a number", attr.span)
      Word(_, _) => ()
    }
  }
  fail("expected a number", attr.span)
}

///|
fn builtin_of(
  word : String,
  span : @moonnaga.Span,
) -> @moonnaga.BuiltIn raise Failed {
  match word {
    "position" => @moonnaga.Position(false)
    "view_index" => @moonnaga.ViewIndex
    "base_instance" => @moonnaga.BaseInstance
    "base_vertex" => @moonnaga.BaseVertex
    "clip_distances" => @moonnaga.ClipDistance
    "cull_distance" => @moonnaga.CullDistance
    "instance_index" => @moonnaga.InstanceIndex
    "point_size" => @moonnaga.PointSize
    "vertex_index" => @moonnaga.VertexIndex
    "draw_index" => @moonnaga.DrawId
    "frag_depth" => @moonnaga.FragDepth
    "point_coord" => @moonnaga.PointCoord
    "front_facing" => @moonnaga.FrontFacing
    "primitive_index" => @moonnaga.PrimitiveIndex
    "sample_index" => @moonnaga.SampleIndex
    "sample_mask" => @moonnaga.SampleMask
    "global_invocation_id" => @moonnaga.GlobalInvocationId
    "local_invocation_id" => @moonnaga.LocalInvocationId
    "local_invocation_index" => @moonnaga.LocalInvocationIndex
    "workgroup_id" => @moonnaga.WorkgroupId
    "workgroup_size" => @moonnaga.WorkgroupSize
    "num_workgroups" => @moonnaga.NumWorkgroups
    "num_subgroups" => @moonnaga.NumSubgroups
    "subgroup_id" => @moonnaga.SubgroupId
    "subgroup_size" => @moonnaga.SubgroupSize
    "subgroup_invocation_id" => @moonnaga.SubgroupInvocationId
    other => fail("`\{other}` is not a builtin", span)
  }
}

///|
fn Builder::declare_signature(
  self : Builder,
  decl : FnDecl,
) -> Unit raise Failed {
  let params = []
  for param in decl.params {
    params.push(self.resolve_type(param.ty))
  }
  let result = match decl.result.ty {
    Some(ty) => Some(self.resolve_type(ty))
    None => None
  }
  let handle = self.shader().functions.add(@moonnaga.Function::new())
  self.signatures[decl.name] = { handle, params, result, }
}

///|
fn Builder::declare_global(self : Builder, decl : VarDecl) -> Unit raise Failed {
  let space = match decl.space {
    None => @moonnaga.Handle
    Some(text) => address_space_of(text, decl.span)
  }
  let ty = match decl.ty {
    Some(expr) => self.resolve_type(expr)
    None => fail("a shader-scope variable needs a type", decl.span)
  }
  let binding = self.resource_binding_of(decl.attrs)
  let init = match decl.init {
    None => None
    Some(expr) => {
      let saved = self.begin_module_scope()
      let handle = self.lower_const_expr(expr)
      self.coerce(handle, ty)
      self.end_module_scope(saved)
      Some(handle)
    }
  }
  let handle = self.shader().global_variables.add({
    name: Some(decl.name),
    space,
    binding,
    ty,
    init,
  })
  self.globals[decl.name] = handle
}

///|
/// The `@group` and `@binding` a resource variable carries.
fn Builder::resource_binding_of(
  self : Builder,
  attrs : Array[Attribute],
) -> @moonnaga.ResourceBinding? raise Failed {
  let group = match find_attribute(attrs, "group") {
    Some(attr) => Some(self.attribute_index(attr))
    None => None
  }
  let binding = match find_attribute(attrs, "binding") {
    Some(attr) => Some(self.attribute_index(attr))
    None => None
  }
  match (group, binding) {
    (Some(group), Some(binding)) => Some({ group, binding, })
    _ => None
  }
}

///|
pub fn address_space_of(
  text : String,
  span : @moonnaga.Span,
) -> @moonnaga.AddressSpace raise Failed {
  let parts = text.split(",").collect()
  let space = match parts[0] {
    "function" => @moonnaga.Function
    "private" => @moonnaga.Private
    "workgroup" => @moonnaga.WorkGroup
    "uniform" => @moonnaga.Uniform
    "storage" => {
      let access = if parts.length() > 1 {
        match parts[1] {
          "read" => @moonnaga.Read
          "write" => @moonnaga.Write
          "read_write" => @moonnaga.ReadWrite
          other => fail("`\{other}` is not an access mode", span)
        }
      } else {
        @moonnaga.Read
      }
      @moonnaga.Storage(access)
    }
    "push_constant" => @moonnaga.PushConstant
    other => fail("`\{other}` is not an address space", span)
  }
  space
}
