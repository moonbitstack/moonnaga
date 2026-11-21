// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A literal as the front end read it. The abstract forms are the ones WGSL
/// gives to an unsuffixed number literal before it is forced into a concrete
/// type; they never survive validation.
#derive(Eq, Debug)
pub(all) enum Literal {
  F64(Double)
  F32(Float)
  U32(UInt32)
  I32(Int32)
  U64(UInt64)
  I64(Int64)
  Bool(Bool)
  AbstractInt(Int64)
  AbstractFloat(Double)
}

///|
#derive(Eq, Debug)
pub(all) enum BinaryOperator {
  Add
  Subtract
  Multiply
  Divide
  Modulo
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
  And
  ExclusiveOr
  InclusiveOr
  LogicalAnd
  LogicalOr
  ShiftLeft
  ShiftRight
}

///|
#derive(Eq, Debug)
pub(all) enum UnaryOperator {
  Negate
  LogicalNot
  BitwiseNot
}

///|
#derive(Eq, Debug)
pub(all) enum MathFunction {
  Abs
  Min
  Max
  Clamp
  Saturate
  Cos
  Cosh
  Sin
  Sinh
  Tan
  Tanh
  Acos
  Asin
  Atan
  Atan2
  Asinh
  Acosh
  Atanh
  Radians
  Degrees
  Ceil
  Floor
  Round
  Fract
  Trunc
  Modf
  Frexp
  Ldexp
  Exp
  Exp2
  Log
  Log2
  Pow
  Dot
  Dot4I8Packed
  Dot4U8Packed
  Outer
  Cross
  Distance
  Length
  Normalize
  FaceForward
  Reflect
  Refract
  Sign
  Fma
  Mix
  Step
  SmoothStep
  Sqrt
  InverseSqrt
  Inverse
  Transpose
  Determinant
  QuantizeToF16
  CountTrailingZeros
  CountLeadingZeros
  CountOneBits
  ReverseBits
  ExtractBits
  InsertBits
  FirstTrailingBit
  FirstLeadingBit
  Pack4x8snorm
  Pack4x8unorm
  Pack2x16snorm
  Pack2x16unorm
  Pack2x16float
  Pack4xI8
  Pack4xU8
  Pack4xI8Clamp
  Pack4xU8Clamp
  Unpack4x8snorm
  Unpack4x8unorm
  Unpack2x16snorm
  Unpack2x16unorm
  Unpack2x16float
  Unpack4xI8
  Unpack4xU8
}

///|
#derive(Eq, Debug)
pub(all) enum RelationalFunction {
  All
  Any
  IsNan
  IsInf
}

///|
#derive(Eq, Debug)
pub(all) enum DerivativeAxis {
  X
  Y
  Width
}

///|
#derive(Eq, Debug)
pub(all) enum DerivativeControl {
  Coarse
  Fine
  None
}

///|
#derive(Eq, Debug)
pub(all) enum ImageQueryKind {
  Size
  NumLevels
  NumLayers
  NumSamples
}

///|
#derive(Eq, Debug)
pub(all) enum SwizzleComponent {
  X
  Y
  Z
  W
}

///|
pub fn SwizzleComponent::to_int(self : SwizzleComponent) -> Int32 {
  match self {
    X => 0
    Y => 1
    Z => 2
    W => 3
  }
}

///|
/// How the level of detail of a sampling operation is chosen.
#derive(Eq, Debug)
pub(all) enum SampleLevel {
  /// The hardware picks, which is what a fragment shader usually wants.
  Auto
  /// The base level, what a non-fragment stage has to use.
  Zero
  Exact(Handle)
  Bias(Handle)
  Gradient(Handle, Handle)
}

///|
/// A conversion from one scalar kind or width to another.
#derive(Eq, Debug)
pub(all) struct AsType {
  kind : ScalarKind
  convert : Int32?
}

///|
#derive(Debug)
pub(all) struct ComposeExpr {
  ty : Handle
  components : Array[Handle]
}

///|
#derive(Debug)
pub(all) struct AccessExpr {
  base : Handle
  index : Handle
}

///|
#derive(Debug)
pub(all) struct AccessIndexExpr {
  base : Handle
  index : Int32
}

///|
#derive(Debug)
pub(all) struct SplatExpr {
  size : VectorSize
  value : Handle
}

///|
#derive(Debug)
pub(all) struct SwizzleExpr {
  size : VectorSize
  vector : Handle
  pattern : Array[SwizzleComponent]
}

///|
#derive(Debug)
pub(all) struct ImageSampleExpr {
  image : Handle
  sampler : Handle
  /// Set by a gather: which component of the four texels comes back.
  gather : SwizzleComponent?
  coordinate : Handle
  array_index : Handle?
  offset : Handle?
  level : SampleLevel
  depth_ref : Handle?
}

///|
#derive(Debug)
pub(all) struct ImageLoadExpr {
  image : Handle
  coordinate : Handle
  array_index : Handle?
  sample : Handle?
  level : Handle?
}

///|
#derive(Debug)
pub(all) struct ImageQueryExpr {
  image : Handle
  query : ImageQueryKind
}

///|
#derive(Debug)
pub(all) struct UnaryExpr {
  op : UnaryOperator
  expr : Handle
}

///|
#derive(Debug)
pub(all) struct BinaryExpr {
  op : BinaryOperator
  left : Handle
  right : Handle
}

///|
#derive(Debug)
pub(all) struct SelectExpr {
  condition : Handle
  accept : Handle
  reject : Handle
}

///|
#derive(Debug)
pub(all) struct DerivativeExpr {
  axis : DerivativeAxis
  ctrl : DerivativeControl
  expr : Handle
}

///|
#derive(Debug)
pub(all) struct RelationalExpr {
  fun : RelationalFunction
  argument : Handle
}

///|
#derive(Debug)
pub(all) struct MathExpr {
  fun : MathFunction
  arg : Handle
  arg1 : Handle?
  arg2 : Handle?
  arg3 : Handle?
}

///|
#derive(Debug)
pub(all) struct AsExpr {
  expr : Handle
  kind : ScalarKind
  convert : Int32?
}

///|
#derive(Debug)
pub(all) struct AtomicResultExpr {
  ty : Handle
  comparison : Bool
}

///|
/// One expression of a function or of a constant initialiser.
///
/// Expressions are a flat arena rather than a tree: a node refers to its
/// operands by handle, and the front end appends in evaluation order. That is
/// what lets a writer decide where a temporary is needed without walking the
/// same subtree twice.
#derive(Debug)
pub(all) enum Expression {
  Literal(Literal)
  Constant(Handle)
  Override(Handle)
  ZeroValue(Handle)
  Compose(ComposeExpr)
  Access(AccessExpr)
  AccessIndex(AccessIndexExpr)
  Splat(SplatExpr)
  Swizzle(SwizzleExpr)
  FunctionArgument(Int32)
  GlobalVariable(Handle)
  LocalVariable(Handle)
  Load(Handle)
  ImageSample(ImageSampleExpr)
  ImageLoad(ImageLoadExpr)
  ImageQuery(ImageQueryExpr)
  Unary(UnaryExpr)
  Binary(BinaryExpr)
  Select(SelectExpr)
  Derivative(DerivativeExpr)
  Relational(RelationalExpr)
  Math(MathExpr)
  As(AsExpr)
  CallResult(Handle)
  AtomicResult(AtomicResultExpr)
  WorkGroupUniformLoadResult(Handle)
  ArrayLength(Handle)
}
