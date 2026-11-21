// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What an atomic operation does to the memory it addresses.
#derive(Eq, Debug)
pub(all) enum AtomicFunction {
  AtomicAdd
  AtomicSubtract
  AtomicAnd
  AtomicExclusiveOr
  AtomicInclusiveOr
  AtomicMin
  AtomicMax
  AtomicExchange
  AtomicCompareExchangeWeak
}

///|
/// Which memories a barrier orders.
#derive(Eq, Debug)
pub(all) enum BarrierKind {
  Workgroup
  Storage
  Texture
}

///|
/// The value a `case` of a switch selects on.
#derive(Eq, Debug)
pub(all) enum SwitchValue {
  I32(Int32)
  U32(UInt32)
  I64(Int64)
  U64(UInt64)
  Default
}

///|
#derive(Debug)
pub(all) struct SwitchCase {
  value : SwitchValue
  body : Array[Statement]
  /// A case that does not end in `break` runs into the next one.
  fall_through : Bool
}

///|
#derive(Debug)
pub(all) struct IfStatement {
  condition : Handle
  accept : Array[Statement]
  reject : Array[Statement]
}

///|
#derive(Debug)
pub(all) struct SwitchStatement {
  selector : Handle
  cases : Array[SwitchCase]
}

///|
#derive(Debug)
pub(all) struct LoopStatement {
  body : Array[Statement]
  continuing : Array[Statement]
  break_if : Handle?
}

///|
#derive(Debug)
pub(all) struct StoreStatement {
  pointer : Handle
  value : Handle
}

///|
#derive(Debug)
pub(all) struct ImageStoreStatement {
  image : Handle
  coordinate : Handle
  array_index : Handle?
  value : Handle
}

///|
#derive(Debug)
pub(all) struct AtomicStatement {
  fun : AtomicFunction
  pointer : Handle
  value : Handle
  result : Handle
}

///|
#derive(Debug)
pub(all) struct WorkGroupUniformLoadStatement {
  pointer : Handle
  result : Handle
}

///|
#derive(Debug)
pub(all) struct CallStatement {
  function : Handle
  arguments : Array[Handle]
  result : Handle?
}

///|
/// One statement of a function body.
///
/// Blocks are statement arrays rather than a nested statement, which keeps the
/// flattening a writer does for `if` and `loop` bodies a matter of walking the
/// array it already has.
#derive(Debug)
pub(all) enum Statement {
  Emit(Handle)
  Block(Array[Statement])
  If(IfStatement)
  Switch(SwitchStatement)
  Loop(LoopStatement)
  Break
  Continue
  Return(Handle?)
  /// `discard`, which ends the invocation without producing output.
  Kill
  ControlBarrier(BarrierKind)
  MemoryBarrier(BarrierKind)
  Store(StoreStatement)
  ImageStore(ImageStoreStatement)
  Atomic(AtomicStatement)
  WorkGroupUniformLoad(WorkGroupUniformLoadStatement)
  Call(CallStatement)
}
