// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The four kinds of scalar WGSL has.
#derive(Eq, Hash, Debug)
pub(all) enum ScalarKind {
  Sint
  Uint
  Float
  Bool
  /// An integer literal whose type the source has not fixed yet. It is
  /// concretised by the first use that needs a width, and never reaches a back
  /// end.
  AbstractInt
  /// The same for a floating-point literal.
  AbstractFloat
}

///|
/// A scalar type: a kind and a width in bytes.
#derive(Eq, Hash, Debug)
pub(all) struct Scalar {
  kind : ScalarKind
  width : Int32
}

///|
pub fn Scalar::new(kind : ScalarKind, width : Int32) -> Scalar {
  { kind, width, }
}

///|
pub fn sint(width : Int32) -> Scalar {
  { kind: Sint, width, }
}

///|
pub fn uint(width : Int32) -> Scalar {
  { kind: Uint, width, }
}

///|
pub fn float(width : Int32) -> Scalar {
  { kind: Float, width, }
}

///|
pub fn boolean() -> Scalar {
  { kind: Bool, width: 4, }
}

///|
pub let scalar_i32 : Scalar = { kind: Sint, width: 4, }

///|
pub let scalar_u32 : Scalar = { kind: Uint, width: 4, }

///|
pub let scalar_f32 : Scalar = { kind: Float, width: 4, }

///|
pub let scalar_f64 : Scalar = { kind: Float, width: 8, }

///|
pub let scalar_i64 : Scalar = { kind: Sint, width: 8, }

///|
pub let scalar_u64 : Scalar = { kind: Uint, width: 8, }

///|
pub let scalar_bool : Scalar = { kind: Bool, width: 4, }

///|
pub fn Scalar::is_float(self : Scalar) -> Bool {
  self.kind == Float || self.kind == AbstractFloat
}

///|
pub fn Scalar::is_integer(self : Scalar) -> Bool {
  self.kind == Sint || self.kind == Uint || self.kind == AbstractInt
}

///|
/// Whether the width is still open, which is true of the abstract types only.
pub fn Scalar::is_abstract(self : Scalar) -> Bool {
  self.kind == AbstractInt || self.kind == AbstractFloat
}

///|
pub fn Scalar::is_bool(self : Scalar) -> Bool {
  self.kind == Bool
}

///|
/// How many components a vector has.
#derive(Eq, Hash, Compare, Debug)
pub(all) enum VectorSize {
  Bi
  Tri
  Quad
}

///|
pub fn VectorSize::to_int(self : VectorSize) -> Int32 {
  match self {
    Bi => 2
    Tri => 3
    Quad => 4
  }
}

///|
/// The vector size with that many components, if there is one.
pub fn VectorSize::from_int(count : Int32) -> VectorSize? {
  match count {
    2 => Some(Bi)
    3 => Some(Tri)
    4 => Some(Quad)
    _ => None
  }
}

///|
/// Where a variable lives, which is what decides who may write it and how it
/// reaches the GPU.
#derive(Eq, Hash, Debug)
pub(all) enum AddressSpace {
  Function
  Private
  WorkGroup
  Uniform
  Storage(StorageAccess)
  PushConstant
  Handle
}

///|
/// The access a storage buffer was declared with.
#derive(Eq, Hash, Debug)
pub(all) enum StorageAccess {
  Read
  Write
  ReadWrite
}

///|
pub fn StorageAccess::may_load(self : StorageAccess) -> Bool {
  match self {
    Read | ReadWrite => true
    Write => false
  }
}

///|
pub fn StorageAccess::may_store(self : StorageAccess) -> Bool {
  match self {
    Write | ReadWrite => true
    Read => false
  }
}

///|
/// The dimensions of a texture.
#derive(Eq, Hash, Debug)
pub(all) enum ImageDimension {
  D1
  D2
  D3
  Cube
}

///|
/// The three ways a handle can reach a texture.
#derive(Eq, Hash, Debug)
pub(all) enum ImageClass {
  Sampling
  Depth
  /// A storage texture, with the access the module declared and the format
  /// name the driver needs.
  Storage(StorageAccess, String)
}

///|
#derive(Eq, Debug)
pub(all) struct ImageType {
  dim : ImageDimension
  arrayed : Bool
  class : ImageClass
}

///|
/// A built-in input or output, named by the WebGPU specification.
#derive(Eq, Hash, Debug)
pub(all) enum BuiltIn {
  Position(Bool)
  ViewIndex
  BaseInstance
  BaseVertex
  ClipDistance
  CullDistance
  InstanceIndex
  PointSize
  VertexIndex
  DrawId
  FragDepth
  PointCoord
  FrontFacing
  PrimitiveIndex
  SampleIndex
  SampleMask
  GlobalInvocationId
  LocalInvocationId
  LocalInvocationIndex
  WorkgroupId
  WorkgroupSize
  NumWorkgroups
  NumSubgroups
  SubgroupId
  SubgroupSize
  SubgroupInvocationId
}

///|
/// What a struct member or an entry point argument is bound to.
#derive(Eq, Debug)
pub(all) enum Binding {
  BuiltIn(BuiltIn)
  Location(Int32)
}

///|
/// The interpolation a fragment input asks for.
#derive(Eq, Debug)
pub(all) enum Interpolation {
  Perspective
  Linear
  Flat
}

///|
/// Where in the pixel an interpolated value is taken.
#derive(Eq, Debug)
pub(all) enum Sampling {
  Center
  Centroid
  Sample
  First
  Either
}

///|
#derive(Eq, Debug)
pub(all) struct InterpolationBinding {
  interpolation : Interpolation
  sampling : Sampling?
}

///|
/// The length of an array.
#derive(Eq, Debug)
pub(all) enum ArraySize {
  /// A length the module fixes itself.
  Fixed(Int32)
  /// A length a pipeline constant fills in.
  Override
  /// A length only the bound buffer knows.
  Dynamic
}

///|
#derive(Debug)
pub(all) struct StructMember {
  name : String
  ty : Handle
  binding : Binding?
  offset : Int32
  interpolate : InterpolationBinding?
}

///|
/// What a type is. A struct's name lives in its [`Type`] rather than here, so
/// two structs are the same type only if they are the same entry.
#derive(Debug)
pub(all) enum TypeInner {
  Scalar(Scalar)
  Vector(VectorType)
  Matrix(MatrixType)
  Atomic(Scalar)
  Pointer(PointerType)
  ValuePointer(ValuePointerType)
  Array(ArrayType)
  Struct(StructType)
  Image(ImageType)
  Sampler(SamplerType)
  AccelerationStructure(AccelerationStructureType)
  RayQuery(RayQueryType)
  BindingArray(BindingArrayType)
}

///|
#derive(Eq, Debug)
pub(all) struct VectorType {
  size : VectorSize
  scalar : Scalar
}

///|
#derive(Eq, Debug)
pub(all) struct MatrixType {
  columns : VectorSize
  rows : VectorSize
  scalar : Scalar
}

///|
#derive(Eq, Debug)
pub(all) struct PointerType {
  base : Handle
  space : AddressSpace
}

///|
#derive(Eq, Debug)
pub(all) struct ValuePointerType {
  size : VectorSize?
  scalar : Scalar
  space : AddressSpace
}

///|
#derive(Eq, Debug)
pub(all) struct ArrayType {
  base : Handle
  size : ArraySize
  stride : Int32
}

///|
#derive(Debug)
pub(all) struct StructType {
  members : Array[StructMember]
  span : Int32
}

///|
#derive(Eq, Debug)
pub(all) struct SamplerType {
  comparison : Bool
}

///|
#derive(Eq, Debug)
pub(all) struct AccelerationStructureType {
  vertex_return : Bool
}

///|
#derive(Eq, Debug)
pub(all) struct RayQueryType {
  vertex_return : Bool
}

///|
#derive(Eq, Debug)
pub(all) struct BindingArrayType {
  base : Handle
  size : ArraySize
}

///|
/// A named type. A named entry is what WGSL can write down; an anonymous one is
/// what the front end synthesises for images, matrices and the like.
#derive(Debug)
pub(all) struct Type {
  name : String?
  inner : TypeInner
}

///|
pub fn Type::new(name : String?, inner : TypeInner) -> Type {
  { name, inner, }
}

///|
/// Whether the value of this type can be held in a variable, passed by value or
/// stored in a buffer. Opaque handles, pointers and unsized arrays cannot.
pub fn TypeInner::is_data(self : TypeInner) -> Bool {
  match self {
    Scalar(_) | Vector(_) | Matrix(_) | Array(_) | Struct(_) => true
    Atomic(_) => true
    Pointer(_) | ValuePointer(_) => false
    Image(_) | Sampler(_) | AccelerationStructure(_) | RayQuery(_) => false
    BindingArray(_) => false
  }
}

///|
pub fn TypeInner::is_sized(self : TypeInner) -> Bool {
  match self {
    Array(array) =>
      match array.size {
        Dynamic => false
        _ => true
      }
    // A struct is sized when its members are, which needs the module to look
    // the member types up; see `Module::is_sized`.
    _ => true
  }
}
