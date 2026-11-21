// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
#derive(Debug)
pub(all) struct Constant {
  name : String?
  ty : Handle
  init : Handle
}

///|
/// A pipeline-overridable constant: a value the module leaves open for the
/// pipeline to fill in.
#derive(Debug)
pub(all) struct Override {
  name : String
  ty : Handle
  init : Handle?
}

///|
#derive(Eq, Debug)
pub(all) struct ResourceBinding {
  group : Int32
  binding : Int32
}

///|
#derive(Debug)
pub(all) struct GlobalVariable {
  name : String?
  space : AddressSpace
  binding : ResourceBinding?
  ty : Handle
  init : Handle?
}

///|
#derive(Debug)
pub(all) struct LocalVariable {
  name : String?
  ty : Handle
  init : Handle?
}

///|
#derive(Debug)
pub(all) struct FunctionArgument {
  name : String?
  ty : Handle
  binding : Binding?
  interpolate : InterpolationBinding?
}

///|
#derive(Debug)
pub(all) struct FunctionResult {
  ty : Handle?
  binding : Binding?
  interpolate : InterpolationBinding?
}

///|
/// A function, its arena of expressions, and the names the source gave to some
/// of them.
#derive(Debug)
pub(all) struct Function {
  name : String?
  arguments : Array[FunctionArgument]
  result : FunctionResult
  local_variables : Arena[LocalVariable]
  expressions : Arena[Expression]
  named_expressions : Map[Int32, String]
  /// The type of every expression, and the address space when it is a pointer.
  /// A back end needs both: WGSL writes `x[i]` for an array and `x.y` for a
  /// struct member, and the two look the same in the expression itself.
  expr_types : Array[Handle]
  expr_spaces : Array[AddressSpace?]
  body : Array[Statement]
}

///|
pub fn Function::new() -> Function {
  {
    name: None,
    arguments: [],
    result: { ty: None, binding: None, interpolate: None, },
    local_variables: Arena::new(),
    expressions: Arena::new(),
    named_expressions: Map([]),
    expr_types: [],
    expr_spaces: [],
    body: [],
  }
}

///|
#derive(Eq, Debug)
pub(all) enum ShaderStage {
  Vertex
  Fragment
  Compute
  Task
  Mesh
}

///|
#derive(Eq, Debug)
pub(all) enum ConservativeDepth {
  GreaterEqual
  LessEqual
  Unchanged
}

///|
#derive(Eq, Debug)
pub(all) struct EarlyDepthTest {
  conservative : ConservativeDepth?
}

///|
/// The interface of one entry point, and the function that implements it.
#derive(Debug)
pub(all) struct EntryPoint {
  name : String
  stage : ShaderStage
  early_depth_test : EarlyDepthTest?
  workgroup_size : Array[Int32]
  /// For each of the three dimensions, the override that replaces the fixed
  /// size, if any.
  workgroup_size_overrides : Array[Handle?]
  function : Handle
}

///|
#derive(Debug)
pub(all) struct SpecialTypes {
  /// The return type of `atomicCompareExchangeWeak`.
  atomic_compare_exchange_result : Handle?
}

///|
pub fn SpecialTypes::empty() -> SpecialTypes {
  { atomic_compare_exchange_result: None, }
}

///|
/// A whole shader module: the types, the values at module scope, the functions
/// and the entry points, all in the order the front end saw them.
#derive(Debug)
pub(all) struct Module {
  types : Arena[Type]
  constants : Arena[Constant]
  overrides : Arena[Override]
  global_variables : Arena[GlobalVariable]
  functions : Arena[Function]
  entry_points : Array[EntryPoint]
  /// The expressions constant initialisers are made of. They live outside any
  /// function because several of them share one.
  const_expressions : Arena[Expression]
  special_types : SpecialTypes
}

///|
pub fn Module::new() -> Module {
  {
    types: Arena::new(),
    constants: Arena::new(),
    overrides: Arena::new(),
    global_variables: Arena::new(),
    functions: Arena::new(),
    entry_points: [],
    const_expressions: Arena::new(),
    special_types: SpecialTypes::empty(),
  }
}

///|
pub fn Module::type_inner(self : Module, handle : Handle) -> TypeInner {
  self.types.get(handle).inner
}

///|
/// Whether every value of this type has one size, which decides whether it may
/// be a local, an argument or a struct member that is not the last one.
pub fn Module::is_sized(self : Module, handle : Handle) -> Bool {
  match self.type_inner(handle) {
    Array(array) =>
      match array.size {
        Dynamic => false
        _ => true
      }
    Struct(structure) => {
      let count = structure.members.length()
      if count == 0 {
        true
      } else {
        self.is_sized(structure.members[count - 1].ty)
      }
    }
    _ => true
  }
}

///|
/// The scalar a scalar-or-vector type is made of.
pub fn Module::scalar_of(self : Module, handle : Handle) -> Scalar? {
  match self.type_inner(handle) {
    Scalar(scalar) => Some(scalar)
    Vector(vector) => Some(vector.scalar)
    _ => None
  }
}

///|
/// How many components a scalar-or-vector type has: one for a scalar.
pub fn Module::components_of(self : Module, handle : Handle) -> Int32? {
  match self.type_inner(handle) {
    Scalar(_) => Some(1)
    Vector(vector) => Some(vector.size.to_int())
    _ => None
  }
}

///|
/// The number of bytes one value of this type occupies in a buffer, as an
/// integer when the type has one.
pub fn Module::size_of(self : Module, handle : Handle) -> Int32 {
  self.layout(handle, 0).size
}

///|
#derive(Eq, Debug)
pub(all) struct Layout {
  size : Int32
  alignment : Int32
}

///|
/// The size and alignment of a type, following the uniform-buffer layout rules
/// of the WGSL specification.
pub fn Module::layout(
  self : Module,
  handle : Handle,
  round_up : Int32,
) -> Layout {
  match self.type_inner(handle) {
    Scalar(scalar) =>
      if scalar.kind == Bool {
        { size: 4, alignment: 4, }
      } else {
        { size: scalar.width, alignment: scalar.width, }
      }
    Vector(vector) => {
      let width = vector.scalar.width
      let count = vector.size.to_int()
      // A vec3 occupies the space of a vec4, and so does its alignment.
      { size: count * width, alignment: vector_alignment(width, count), }
    }
    Matrix(matrix) => {
      let width = matrix.scalar.width
      let rows = matrix.rows.to_int()
      let columns = matrix.columns.to_int()
      let alignment = vector_alignment(width, rows)
      { size: alignment * columns, alignment, }
    }
    Atomic(_) => { size: 4, alignment: 4, }
    Array(array) => {
      let element = self.layout(array.base, 0)
      let stride = align_to(array.stride_or(element.size), element.alignment)
      match array.size {
        Fixed(count) => { size: stride * count, alignment: element.alignment, }
        _ => { size: 0, alignment: element.alignment, }
      }
    }
    Struct(structure) => {
      let mut offset = 0
      let mut alignment = 1
      for field in structure.members {
        let member_layout = self.layout(field.ty, 0)
        if member_layout.alignment > alignment {
          alignment = member_layout.alignment
        }
        offset = align_to(offset, member_layout.alignment) + member_layout.size
      }
      { size: structure.span, alignment, }
    }
    _ => { size: round_up, alignment: 1, }
  }
}

///|
fn ArrayType::stride_or(self : ArrayType, fallback : Int32) -> Int32 {
  if self.stride > 0 {
    self.stride
  } else {
    fallback
  }
}

///|
/// The alignment a vector of `count` components of that width has: the size
/// rounded up to a power of two, which is what makes a `vec3` align like a
/// `vec4`.
pub fn vector_alignment(width : Int32, count : Int32) -> Int32 {
  if count >= 3 {
    4 * width
  } else {
    count * width
  }
}

///|
pub fn align_to(value : Int32, alignment : Int32) -> Int32 {
  if alignment <= 1 {
    value
  } else {
    (value + alignment - 1) / alignment * alignment
  }
}

///|
/// The outermost type name a reader would recognise, for diagnostics.
pub fn TypeInner::name(self : TypeInner) -> String {
  match self {
    Scalar(scalar) => scalar_name(scalar)
    Vector(vector) =>
      "vec\{vector.size.to_int()}<\{scalar_name(vector.scalar)}>"
    Matrix(matrix) =>
      "mat\{matrix.columns.to_int()}x\{matrix.rows.to_int()}<\{scalar_name(matrix.scalar)}>"
    Atomic(scalar) => "atomic_op<\{scalar_name(scalar)}>"
    Pointer(_) => "ptr"
    ValuePointer(_) => "ptr"
    Array(_) => "array"
    Struct(_) => "struct"
    Image(_) => "texture"
    Sampler(_) => "sampler"
    AccelerationStructure(_) => "acceleration_structure"
    RayQuery(_) => "ray_query"
    BindingArray(_) => "binding_array"
  }
}

///|
pub fn scalar_name(scalar : Scalar) -> String {
  match scalar.kind {
    Sint => if scalar.width == 8 { "i64" } else { "i32" }
    Uint => if scalar.width == 8 { "u64" } else { "u32" }
    Float =>
      if scalar.width == 8 {
        "f64"
      } else if scalar.width == 2 {
        "f16"
      } else {
        "f32"
      }
    Bool => "bool"
    AbstractInt => "abstract-int"
    AbstractFloat => "abstract-float"
  }
}

///|
/// The name of a type as WGSL writes it, which is what diagnostics quote.
pub fn Module::type_name(self : Module, handle : Handle) -> String {
  let ty = self.types.get(handle)
  match ty.name {
    Some(name) => name
    None => ty.inner.name()
  }
}
