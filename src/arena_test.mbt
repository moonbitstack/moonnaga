// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "an arena hands out handles in order" {
  let arena : @moonnaga.Arena[String] = @moonnaga.Arena::new()
  let first = arena.add("a")
  let second = arena.add("b")
  assert_eq(first.to_int(), 0)
  assert_eq(second.to_int(), 1)
  assert_eq(arena.get(second), "b")
  assert_eq(arena.len(), 2)
}

///|
test "compacting drops the entries a predicate rejects" {
  let arena : @moonnaga.Arena[Int32] = @moonnaga.Arena::new()
  ignore(arena.add(1))
  ignore(arena.add(2))
  ignore(arena.add(3))
  let (kept, remap) = arena.compact(fn(_, value) { value != 2 })
  assert_eq(kept.len(), 2)
  assert_eq(remap[0], 0)
  assert_eq(remap[1], -1)
  assert_eq(remap[2], 1)
}
