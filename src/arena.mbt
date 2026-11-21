// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A reference to one entry of an [`Arena`].
///
/// A handle carries nothing but a position, so it says nothing about which
/// arena issued it. Every use that hands a handle to an arena of another kind
/// is a compiler bug rather than a diagnostic, and is reported as one.
#derive(Eq, Hash, Compare, Debug)
pub(all) struct Handle {
  index : Int32
}

///|
pub fn Handle::new(index : Int32) -> Handle {
  { index, }
}

///|
pub fn Handle::to_int(self : Handle) -> Int32 {
  self.index
}

///|
/// A dense, append-only store, which is how the module keeps types,
/// constants, globals, functions, expressions and statements addressable.
///
/// Nothing is ever removed: the front end appends, and a later pass rewrites
/// entries in place. Order is insertion order, and it is load-bearing — the
/// writers walk the arenas in that order, so a module that has been compacted
/// writes out differently from one that has not.
pub(all) struct Arena[T] {
  items : Array[T]
}

///|
pub fn[T] Arena::new() -> Arena[T] {
  { items: [], }
}

///|
pub fn[T] Arena::add(self : Arena[T], value : T) -> Handle {
  let handle = { index: self.items.length(), }
  self.items.push(value)
  handle
}

///|
pub fn[T] Arena::len(self : Arena[T]) -> Int32 {
  self.items.length()
}

///|
pub fn[T] Arena::is_empty(self : Arena[T]) -> Bool {
  self.items.is_empty()
}

///|
fn[T] Arena::check(self : Arena[T], handle : Handle) -> Unit {
  let index = handle.index
  if index < 0 || index >= self.items.length() {
    abort(
      "handle \{index} is outside an arena of \{self.items.length()} entries",
    )
  }
}

///|
pub fn[T] Arena::get(self : Arena[T], handle : Handle) -> T {
  self.check(handle)
  self.items[handle.index]
}

///|
pub fn[T] Arena::set(self : Arena[T], handle : Handle, value : T) -> Unit {
  self.check(handle)
  self.items[handle.index] = value
}

///|
pub fn[T] Arena::get_or(self : Arena[T], handle : Handle, fallback : T) -> T {
  let index = handle.index
  if index < 0 || index >= self.items.length() {
    fallback
  } else {
    self.items[index]
  }
}

///|
/// The index of the first entry for which `pred` holds.
pub fn[T] Arena::find(self : Arena[T], pred : (T) -> Bool) -> Handle? {
  for index in 0..<self.items.length() {
    if pred(self.items[index]) {
      return Some({ index, })
    }
  }
  None
}

///|
pub fn[T] Arena::iter(self : Arena[T]) -> Iter[T] {
  self.items.iter()
}

///|
/// Walks the arena in index order, handing out the handle and the entry.
pub fn[T] Arena::each(self : Arena[T], visit : (Handle, T) -> Unit) -> Unit {
  for index in 0..<self.items.length() {
    visit({ index, }, self.items[index])
  }
}

///|
/// Rebuilds the arena from the entries `keep` selects, remapping handles.
///
/// The writers name temporaries after handle indices, so a module that still
/// holds entries nobody refers to writes out with gaps in those names. A
/// compaction pass drops the unreachable entries first; this is the mechanism
/// it uses, and the remap table it returns is how the caller rewrites its own
/// references.
pub fn[T] Arena::compact(
  self : Arena[T],
  keep : (Handle, T) -> Bool,
) -> (Arena[T], Array[Int32]) {
  let kept = Arena::new()
  let remap = []
  for index in 0..<self.items.length() {
    let handle = { index, }
    if keep(handle, self.items[index]) {
      remap.push(kept.add(self.items[index]).index)
    } else {
      remap.push(-1)
    }
  }
  (kept, remap)
}

///|
pub impl[T : Debug] Debug for Arena[T] with fn to_repr(self) {
  Repr::opaque_("Arena", Repr::array(self.items.map(x => Repr(x))))
}
