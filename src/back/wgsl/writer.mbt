// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The writer's state: the module, the names assigned so far, and the lines
/// waiting to be joined.
///
/// WGSL puts types, constants, globals and functions in one namespace, so they
/// share a single namer; locals and arguments of a function get their own.
pub(all) struct Writer {
  shader : @moonnaga.Module
  namer : Namer
  type_names : Map[Int32, String]
  const_names : Map[Int32, String]
  global_names : Map[Int32, String]
  function_names : Map[Int32, String]
  lines : Array[String]
  mut indent : Int32
  mut temps : Int32
  // Per function:
  mut local_names : Map[Int32, String]
  mut expr_names : Map[Int32, String]
  mut argument_names : Array[String]
  mut written : Map[Int32, Bool]
}

///|
pub fn Writer::new(shader : @moonnaga.Module) -> Writer {
  {
    shader,
    namer: Namer::new(),
    type_names: Map([]),
    const_names: Map([]),
    global_names: Map([]),
    function_names: Map([]),
    lines: [],
    indent: 0,
    temps: 0,
    local_names: Map([]),
    expr_names: Map([]),
    argument_names: [],
    written: Map([]),
  }
}

///|
/// Writes a whole module as WGSL text.
pub fn write_module(shader : @moonnaga.Module) -> String {
  let writer = Writer::new(shader)
  writer.assign_names()
  writer.write_structs()
  writer.write_constants()
  writer.write_globals()
  writer.write_functions()
  writer.write_entry_points()
  writer.finish()
}

///|
fn Writer::assign_names(self : Writer) -> Unit {
  for index in 0..<self.shader.types.len() {
    let ty = self.shader.types.get(@moonnaga.Handle::new(index))
    match ty.name {
      Some(name) => self.type_names[index] = self.namer.unique(name)
      None => ()
    }
  }
  self.shader.constants.each(fn(handle, constant) {
    let name = match constant.name {
      Some(name) => name
      None => "const" + handle.to_int().to_string()
    }
    self.const_names[handle.to_int()] = self.namer.unique(name)
  })
  self.shader.global_variables.each(fn(handle, global) {
    let name = match global.name {
      Some(name) => name
      None => "global" + handle.to_int().to_string()
    }
    self.global_names[handle.to_int()] = self.namer.unique(name)
  })
  self.shader.functions.each(fn(handle, function) {
    let name = match function.name {
      Some(name) => name
      None => "func" + handle.to_int().to_string()
    }
    self.function_names[handle.to_int()] = self.namer.unique(name)
  })
  // An entry point is a function: it keeps the name the function already has.
  for entry in self.shader.entry_points {
    match self.function_names.get(entry.function.to_int()) {
      Some(_) => ()
      None =>
        self.function_names[entry.function.to_int()] = self.namer.unique(
          entry.name,
        )
    }
  }
}

///|
fn Writer::finish(self : Writer) -> String {
  let builder = StringBuilder()
  let mut end = self.lines.length()
  // The file ends after the last line of the last declaration, not after the
  // blank line that separates it from what follows.
  while end > 0 && self.lines[end - 1] == "" {
    end = end - 1
  }
  for index in 0..<end {
    builder.write_string(self.lines[index])
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
fn Writer::line(self : Writer, text : String) -> Unit {
  let mut padding = ""
  for _ in 0..<self.indent {
    padding = padding + "    "
  }
  self.lines.push(padding + text)
}

///|
fn Writer::blank(self : Writer) -> Unit {
  if !self.lines.is_empty() && self.lines[self.lines.length() - 1] != "" {
    self.lines.push("")
  }
}

///|
fn Writer::temp(self : Writer) -> String {
  let name = "_e" + self.temps.to_string()
  self.temps = self.temps + 1
  name
}

///|
fn Writer::write_structs(self : Writer) -> Unit {
  for index in 0..<self.shader.types.len() {
    let handle = @moonnaga.Handle::new(index)
    let ty = self.shader.types.get(handle)
    match ty.inner {
      Struct(structure) => {
        let name = match self.type_names.get(index) {
          Some(name) => name
          None => continue
        }
        self.line("struct " + name + " {")
        self.indent = self.indent + 1
        for field in structure.members {
          let attributes = self.binding_text(field.binding, field.interpolate)
          let separator = if attributes.is_empty() { "" } else { " " }
          self.line(
            attributes +
            separator +
            field.name +
            ": " +
            self.type_text(field.ty) +
            ",",
          )
        }
        self.indent = self.indent - 1
        self.line("}")
        self.blank()
      }
      _ => ()
    }
  }
}

///|
fn Writer::binding_text(
  _self : Writer,
  binding : @moonnaga.Binding?,
  interpolate : @moonnaga.InterpolationBinding?,
) -> String {
  let parts = []
  match binding {
    Some(@moonnaga.BuiltIn(builtin)) =>
      parts.push("@builtin(" + builtin_text(builtin) + ")")
    Some(@moonnaga.Location(index)) =>
      parts.push("@location(" + index.to_string() + ")")
    None => ()
  }
  match interpolate {
    Some(interpolation) => {
      let text = match interpolation.interpolation {
        @moonnaga.Perspective => "perspective"
        @moonnaga.Linear => "linear"
        @moonnaga.Flat => "flat"
      }
      let sampling = match interpolation.sampling {
        Some(@moonnaga.Center) => ", center"
        Some(@moonnaga.Centroid) => ", centroid"
        Some(@moonnaga.Sample) => ", sample"
        Some(@moonnaga.First) => ", first"
        Some(@moonnaga.Either) => ", either"
        None => ""
      }
      parts.push("@interpolate(" + text + sampling + ")")
    }
    None => ()
  }
  join_with(parts, " ")
}

///|
fn builtin_text(builtin : @moonnaga.BuiltIn) -> String {
  match builtin {
    @moonnaga.Position(_) => "position"
    @moonnaga.ViewIndex => "view_index"
    @moonnaga.BaseInstance => "base_instance"
    @moonnaga.BaseVertex => "base_vertex"
    @moonnaga.ClipDistance => "clip_distances"
    @moonnaga.CullDistance => "cull_distance"
    @moonnaga.InstanceIndex => "instance_index"
    @moonnaga.PointSize => "point_size"
    @moonnaga.VertexIndex => "vertex_index"
    @moonnaga.DrawId => "draw_index"
    @moonnaga.FragDepth => "frag_depth"
    @moonnaga.PointCoord => "point_coord"
    @moonnaga.FrontFacing => "front_facing"
    @moonnaga.PrimitiveIndex => "primitive_index"
    @moonnaga.SampleIndex => "sample_index"
    @moonnaga.SampleMask => "sample_mask"
    @moonnaga.GlobalInvocationId => "global_invocation_id"
    @moonnaga.LocalInvocationId => "local_invocation_id"
    @moonnaga.LocalInvocationIndex => "local_invocation_index"
    @moonnaga.WorkgroupId => "workgroup_id"
    @moonnaga.WorkgroupSize => "workgroup_size"
    @moonnaga.NumWorkgroups => "num_workgroups"
    @moonnaga.NumSubgroups => "num_subgroups"
    @moonnaga.SubgroupId => "subgroup_id"
    @moonnaga.SubgroupSize => "subgroup_size"
    @moonnaga.SubgroupInvocationId => "subgroup_invocation_id"
  }
}

///|
pub fn join_with(parts : Array[String], separator : String) -> String {
  let builder = StringBuilder()
  for index in 0..<parts.length() {
    if index > 0 {
      builder.write_string(separator)
    }
    builder.write_string(parts[index])
  }
  builder.to_string()
}

///|
fn Writer::write_constants(self : Writer) -> Unit {
  let mut wrote = false
  for index in 0..<self.shader.constants.len() {
    let handle = @moonnaga.Handle::new(index)
    let constant = self.shader.constants.get(handle)
    match constant.name {
      Some(_) => {
        let name = self.const_names.get(index).unwrap_or("const")
        let text = self.module_const_text(constant.init)
        self.line(
          "const " +
          name +
          ": " +
          self.type_text(constant.ty) +
          " = " +
          text +
          ";",
        )
        wrote = true
      }
      None => ()
    }
  }
  if wrote {
    self.blank()
  }
}

///|
fn Writer::write_globals(self : Writer) -> Unit {
  let mut wrote = false
  for index in 0..<self.shader.global_variables.len() {
    let handle = @moonnaga.Handle::new(index)
    let global = self.shader.global_variables.get(handle)
    let name = self.global_names.get(index).unwrap_or("global")
    let attributes = match global.binding {
      Some(binding) =>
        "@group(" +
        binding.group.to_string() +
        ") @binding(" +
        binding.binding.to_string() +
        ") "
      None => ""
    }
    if !attributes.is_empty() {
      self.line(attributes)
    }
    let space = match global.space {
      @moonnaga.Handle => "var "
      other => "var<" + space_text(other) + "> "
    }
    let init = match global.init {
      Some(value) => " = " + self.module_const_text(value)
      None => ""
    }
    self.line(space + name + ": " + self.type_text(global.ty) + init + ";")
    wrote = true
  }
  if wrote {
    self.blank()
  }
}

///|
/// A namer that has every module-scope name reserved, which is the scope a
/// function's arguments and locals are declared in.
fn Writer::local_namer(self : Writer) -> Namer {
  let namer = Namer::new()
  for entry in self.type_names {
    namer.reserve(entry.1)
  }
  for entry in self.const_names {
    namer.reserve(entry.1)
  }
  for entry in self.global_names {
    namer.reserve(entry.1)
  }
  for entry in self.function_names {
    namer.reserve(entry.1)
  }
  namer
}
