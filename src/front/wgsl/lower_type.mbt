// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The module's types, with the lookup that keeps one entry per distinct type:
/// two `vec4<f32>` in the source become one handle, which is what lets a
/// comparison of types be a comparison of handles.
pub(all) struct TypeTable {
  shader : @moonnaga.Module
  keys : Map[String, @moonnaga.Handle]
  named : Map[String, @moonnaga.Handle]
}

///|
pub fn TypeTable::new() -> TypeTable {
  { shader: @moonnaga.Module::new(), keys: Map([]), named: Map([]), }
}

///|
fn TypeTable::intern(
  self : TypeTable,
  key : String,
  ty : @moonnaga.Type,
) -> @moonnaga.Handle {
  match self.keys.get(key) {
    Some(handle) => handle
    None => {
      let handle = self.shader.types.add(ty)
      self.keys[key] = handle
      handle
    }
  }
}

///|
pub fn TypeTable::scalar_type(
  self : TypeTable,
  scalar : @moonnaga.Scalar,
) -> @moonnaga.Handle {
  self.intern(
    "s:\{@moonnaga.scalar_name(scalar)}",
    @moonnaga.Type::new(None, Scalar(scalar)),
  )
}

///|
pub fn TypeTable::vector_type(
  self : TypeTable,
  size : @moonnaga.VectorSize,
  scalar : @moonnaga.Scalar,
) -> @moonnaga.Handle {
  self.intern(
    "v:\{size.to_int()}:\{@moonnaga.scalar_name(scalar)}",
    @moonnaga.Type::new(None, Vector({ size, scalar, })),
  )
}

///|
pub fn TypeTable::matrix_type(
  self : TypeTable,
  columns : @moonnaga.VectorSize,
  rows : @moonnaga.VectorSize,
  scalar : @moonnaga.Scalar,
) -> @moonnaga.Handle {
  self.intern(
    "m:\{columns.to_int()}x\{rows.to_int()}:\{@moonnaga.scalar_name(scalar)}",
    @moonnaga.Type::new(None, Matrix({ columns, rows, scalar, })),
  )
}

///|
pub fn TypeTable::atomic_type(
  self : TypeTable,
  scalar : @moonnaga.Scalar,
) -> @moonnaga.Handle {
  self.intern(
    "atom:\{@moonnaga.scalar_name(scalar)}",
    @moonnaga.Type::new(None, Atomic(scalar)),
  )
}

///|
pub fn TypeTable::array_type(
  self : TypeTable,
  base : @moonnaga.Handle,
  size : @moonnaga.ArraySize,
) -> @moonnaga.Handle {
  let stride = self.stride_of(base)
  let size_key = match size {
    Fixed(count) => count.to_string()
    Override => "?"
    Dynamic => ""
  }
  self.intern(
    "a:\{base.to_int()}:\{size_key}",
    @moonnaga.Type::new(None, Array({ base, size, stride, })),
  )
}

///|
/// The stride an array of that element type uses: the element's size rounded up
/// to its alignment, which is what makes a `vec3` array skip the fourth lane.
fn TypeTable::stride_of(self : TypeTable, base : @moonnaga.Handle) -> Int32 {
  let layout = self.shader.layout(base, 0)
  @moonnaga.align_to(layout.size, layout.alignment)
}

///|
pub fn TypeTable::image_type(
  self : TypeTable,
  dim : @moonnaga.ImageDimension,
  arrayed : Bool,
  class_ : @moonnaga.ImageClass,
) -> @moonnaga.Handle {
  let key = "img:" +
    dimension_code(dim) +
    ":" +
    arrayed.to_string() +
    ":" +
    class_code(class_)
  self.intern(
    key,
    @moonnaga.Type::new(None, Image({ dim, arrayed, class: class_, })),
  )
}

///|
pub fn TypeTable::sampler_type(
  self : TypeTable,
  comparison : Bool,
) -> @moonnaga.Handle {
  self.intern(
    "sampler:\{comparison}",
    @moonnaga.Type::new(None, Sampler({ comparison, })),
  )
}

///|
pub fn TypeTable::pointer_type(
  self : TypeTable,
  base : @moonnaga.Handle,
  space : @moonnaga.AddressSpace,
) -> @moonnaga.Handle {
  self.intern(
    "ptr:" + base.to_int().to_string() + ":" + space_code(space),
    @moonnaga.Type::new(None, Pointer({ base, space, })),
  )
}

///|
pub fn TypeTable::binding_array_type(
  self : TypeTable,
  base : @moonnaga.Handle,
  size : @moonnaga.ArraySize,
) -> @moonnaga.Handle {
  let size_key = match size {
    Fixed(count) => count.to_string()
    Override => "?"
    Dynamic => ""
  }
  self.intern(
    "barray:\{base.to_int()}:\{size_key}",
    @moonnaga.Type::new(None, BindingArray({ base, size, })),
  )
}

///|
/// Registers a struct under its source name, replacing the member offsets with
/// the ones the uniform-buffer layout gives.
pub fn TypeTable::struct_type(
  self : TypeTable,
  name : String,
  members : Array[@moonnaga.StructMember],
) -> @moonnaga.Handle {
  let laid_out = []
  let mut offset = 0
  let mut alignment = 1
  for field in members {
    let layout = self.shader.layout(field.ty, 0)
    if layout.alignment > alignment {
      alignment = layout.alignment
    }
    offset = @moonnaga.align_to(offset, layout.alignment)
    laid_out.push({ ..field, offset, })
    offset = offset + layout.size
  }
  let span = @moonnaga.align_to(offset, alignment)
  let handle = self.shader.types.add(
    @moonnaga.Type::new(Some(name), Struct({ members: laid_out, span, })),
  )
  self.named[name] = handle
  handle
}

///|
pub fn TypeTable::bind_name(
  self : TypeTable,
  name : String,
  handle : @moonnaga.Handle,
) -> Unit {
  self.named[name] = handle
}

///|
fn dimension_code(dim : @moonnaga.ImageDimension) -> String {
  match dim {
    @moonnaga.D1 => "1d"
    @moonnaga.D2 => "2d"
    @moonnaga.D3 => "3d"
    @moonnaga.Cube => "cube"
  }
}

///|
fn class_code(class_ : @moonnaga.ImageClass) -> String {
  match class_ {
    @moonnaga.Sampling => "sampling"
    @moonnaga.Depth => "depth"
    @moonnaga.Storage(access, format) =>
      "storage" + storage_code(access) + format
  }
}

///|
fn storage_code(access : @moonnaga.StorageAccess) -> String {
  match access {
    @moonnaga.Read => "r"
    @moonnaga.Write => "w"
    @moonnaga.ReadWrite => "rw"
  }
}

///|
fn space_code(space : @moonnaga.AddressSpace) -> String {
  match space {
    @moonnaga.Function => "fn"
    @moonnaga.Private => "private"
    @moonnaga.WorkGroup => "workgroup"
    @moonnaga.Uniform => "uniform"
    @moonnaga.Storage(access) => "storage" + storage_code(access)
    @moonnaga.PushConstant => "push"
    @moonnaga.Handle => "handle"
  }
}

///|
pub fn TypeTable::lookup(self : TypeTable, name : String) -> @moonnaga.Handle? {
  self.named.get(name)
}
