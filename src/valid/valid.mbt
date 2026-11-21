// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The optional language features a validation run allows. Each one matches a
/// WebGPU feature: a module that needs one is refused unless it is asked for,
/// which is what keeps a shader from being accepted here and refused by the
/// device that has to run it.
#derive(Eq, Debug)
pub(all) struct Capabilities {
  f16 : Bool
  f64 : Bool
  int64 : Bool
  push_constant : Bool
  clip_distances : Bool
  dual_source_blending : Bool
}

///|
/// What a WebGPU device offers without asking for anything.
pub let capabilities_default : Capabilities = {
  f16: false,
  f64: false,
  int64: false,
  push_constant: false,
  clip_distances: false,
  dual_source_blending: false,
}

///|
/// Everything this library can check for, which is what a test wants.
pub let capabilities_all : Capabilities = {
  f16: true,
  f64: true,
  int64: true,
  push_constant: true,
  clip_distances: true,
  dual_source_blending: true,
}

///|
/// Which rules to run. A back end that trusts its input runs them all; a tool
/// that only wants the module shape can turn the type rules off.
#derive(Eq, Debug)
pub(all) struct ValidationFlags {
  types : Bool
  entry_points : Bool
  resources : Bool
}

///|
pub let validation_flags_all : ValidationFlags = {
  types: true,
  entry_points: true,
  resources: true,
}

///|
/// A rule the module breaks.
#derive(Eq, Debug)
pub(all) struct ValidationError {
  message : String
  /// The declaration the error is about: a function, a global, a struct.
  subject : String
}

///|
/// What a valid module gives a back end: the entry points, and how many calls
/// each function can reach, which is what tells a back end whether a function
/// is dead.
#derive(Debug)
pub(all) struct ModuleInfo {
  entry_points : Array[@moonnaga.EntryPoint]
}

///|
fn refuse(message : String, subject : String) -> ValidationError {
  { message, subject, }
}

///|
/// Checks a module against the rules of the language and the capabilities the
/// caller has.
pub fn validate(
  shader : @moonnaga.Module,
  capabilities~ : Capabilities = capabilities_default,
  flags~ : ValidationFlags = validation_flags_all,
) -> Result[ModuleInfo, ValidationError] {
  match check_types(shader, capabilities) {
    Some(error) => return Err(error)
    None => ()
  }
  if flags.entry_points {
    match check_entry_points(shader, capabilities) {
      Some(error) => return Err(error)
      None => ()
    }
  }
  if flags.resources {
    match check_resources(shader, capabilities) {
      Some(error) => return Err(error)
      None => ()
    }
  }
  Ok({ entry_points: shader.entry_points, })
}

///|
/// Every type the module names is one the enabled capabilities allow.
fn check_types(
  shader : @moonnaga.Module,
  capabilities : Capabilities,
) -> ValidationError? {
  for index in 0..<shader.types.len() {
    let handle = @moonnaga.Handle::new(index)
    let ty = shader.types.get(handle)
    match ty.inner {
      @moonnaga.Scalar(scalar) =>
        match scalar_feature(scalar) {
          Some("f16") =>
            if !capabilities.f16 {
              return Some(refuse("`f16` is not enabled", type_subject(ty)))
            }
          Some("f64") =>
            if !capabilities.f64 {
              return Some(refuse("`f64` is not enabled", type_subject(ty)))
            }
          Some("i64") =>
            if !capabilities.int64 {
              return Some(
                refuse("64-bit integers are not enabled", type_subject(ty)),
              )
            }
          _ => ()
        }
      @moonnaga.Vector(vector) =>
        match scalar_feature(vector.scalar) {
          Some("f16") =>
            if !capabilities.f16 {
              return Some(refuse("`f16` is not enabled", type_subject(ty)))
            }
          Some("f64") =>
            if !capabilities.f64 {
              return Some(refuse("`f64` is not enabled", type_subject(ty)))
            }
          Some("i64") =>
            if !capabilities.int64 {
              return Some(
                refuse("64-bit integers are not enabled", type_subject(ty)),
              )
            }
          _ => ()
        }
      @moonnaga.Struct(structure) =>
        if structure.members.is_empty() {
          return Some(
            refuse("a struct needs at least one field", type_subject(ty)),
          )
        }
      @moonnaga.Array(array) =>
        if array.stride <= 0 {
          return Some(refuse("an array needs a stride", type_subject(ty)))
        }
      _ => ()
    }
  }
  None
}

///|
fn type_subject(ty : @moonnaga.Type) -> String {
  match ty.name {
    Some(name) => "type " + name
    None => "type " + ty.inner.name()
  }
}

///|
/// The feature a scalar needs, if it needs one.
fn scalar_feature(scalar : @moonnaga.Scalar) -> String? {
  match scalar.kind {
    @moonnaga.Float =>
      if scalar.width == 2 {
        Some("f16")
      } else if scalar.width == 8 {
        Some("f64")
      } else {
        None
      }
    @moonnaga.Sint | @moonnaga.Uint =>
      if scalar.width == 8 {
        Some("i64")
      } else {
        None
      }
    _ => None
  }
}

///|
/// Entry points: one stage each, a workgroup size for the compute ones, and no
/// two arguments claiming the same location or builtin.
fn check_entry_points(
  shader : @moonnaga.Module,
  capabilities : Capabilities,
) -> ValidationError? {
  for entry in shader.entry_points {
    if entry.stage == @moonnaga.Compute {
      for dimension in entry.workgroup_size {
        if dimension <= 0 {
          return Some(
            refuse("a compute entry point needs a workgroup size", entry.name),
          )
        }
      }
    }
    let function = shader.functions.get(entry.function)
    let locations = Map([])
    let builtins = Map([])
    for argument in function.arguments {
      match argument.binding {
        Some(@moonnaga.Location(index)) =>
          match locations.get(index) {
            Some(_) =>
              return Some(
                refuse(
                  "two arguments share location " + index.to_string(),
                  entry.name,
                ),
              )
            None => locations[index] = true
          }
        Some(@moonnaga.BuiltIn(builtin)) => {
          let key = builtin_key(builtin)
          match builtins.get(key) {
            Some(_) =>
              return Some(
                refuse("two arguments share the builtin " + key, entry.name),
              )
            None => builtins[key] = true
          }
          if builtin == @moonnaga.ClipDistance && !capabilities.clip_distances {
            return Some(refuse("`clip_distances` is not enabled", entry.name))
          }
        }
        None => ()
      }
    }
    match function.result.binding {
      Some(@moonnaga.BuiltIn(builtin)) =>
        if builtin == @moonnaga.ClipDistance && !capabilities.clip_distances {
          return Some(refuse("`clip_distances` is not enabled", entry.name))
        }
      _ => ()
    }
  }
  None
}

///|
fn builtin_key(builtin : @moonnaga.BuiltIn) -> String {
  match builtin {
    @moonnaga.Position(_) => "position"
    @moonnaga.ViewIndex => "view_index"
    @moonnaga.FragDepth => "frag_depth"
    @moonnaga.FrontFacing => "front_facing"
    @moonnaga.SampleIndex => "sample_index"
    @moonnaga.SampleMask => "sample_mask"
    @moonnaga.GlobalInvocationId => "global_invocation_id"
    @moonnaga.LocalInvocationId => "local_invocation_id"
    @moonnaga.LocalInvocationIndex => "local_invocation_index"
    @moonnaga.WorkgroupId => "workgroup_id"
    @moonnaga.WorkgroupSize => "workgroup_size"
    @moonnaga.NumWorkgroups => "num_workgroups"
    @moonnaga.InstanceIndex => "instance_index"
    @moonnaga.VertexIndex => "vertex_index"
    @moonnaga.PointSize => "point_size"
    @moonnaga.PointCoord => "point_coord"
    @moonnaga.PrimitiveIndex => "primitive_index"
    @moonnaga.ClipDistance => "clip_distances"
    @moonnaga.CullDistance => "cull_distance"
    @moonnaga.DrawId => "draw_index"
    @moonnaga.BaseInstance => "base_instance"
    @moonnaga.BaseVertex => "base_vertex"
    @moonnaga.NumSubgroups => "num_subgroups"
    @moonnaga.SubgroupId => "subgroup_id"
    @moonnaga.SubgroupSize => "subgroup_size"
    @moonnaga.SubgroupInvocationId => "subgroup_invocation_id"
  }
}

///|
/// Variables at module scope: where each may live, and what each may hold.
fn check_resources(
  shader : @moonnaga.Module,
  capabilities : Capabilities,
) -> ValidationError? {
  for index in 0..<shader.global_variables.len() {
    let global = shader.global_variables.get(@moonnaga.Handle::new(index))
    let subject = match global.name {
      Some(name) => "variable " + name
      None => "variable " + index.to_string()
    }
    match global.space {
      @moonnaga.Uniform =>
        if !shader.is_sized(global.ty) {
          return Some(
            refuse("a uniform variable must have a sized type", subject),
          )
        }
      @moonnaga.Storage(_) => ()
      @moonnaga.PushConstant =>
        if !capabilities.push_constant {
          return Some(refuse("`push_constant` is not enabled", subject))
        }
      @moonnaga.Handle =>
        match shader.type_inner(global.ty) {
          @moonnaga.Image(_) | @moonnaga.Sampler(_) => ()
          _ =>
            return Some(
              refuse(
                "a resource variable must be a texture or a sampler", subject,
              ),
            )
        }
      @moonnaga.WorkGroup =>
        match shader.type_inner(global.ty) {
          @moonnaga.Image(_) | @moonnaga.Sampler(_) =>
            return Some(
              refuse("a texture cannot live in the workgroup space", subject),
            )
          _ => ()
        }
      _ => ()
    }
    // A resource variable needs both halves of its binding, or neither.
    match global.binding {
      Some(_) =>
        match global.space {
          @moonnaga.Uniform | @moonnaga.Storage(_) | @moonnaga.Handle => ()
          _ =>
            return Some(
              refuse("only a resource variable takes a binding", subject),
            )
        }
      None =>
        match global.space {
          @moonnaga.Uniform | @moonnaga.Storage(_) | @moonnaga.Handle =>
            return Some(refuse("a resource variable needs a binding", subject))
          _ => ()
        }
    }
  }
  None
}
