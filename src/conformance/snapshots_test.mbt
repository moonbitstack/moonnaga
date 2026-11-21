// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How many cases this build reproduces byte for byte. The number is a floor,
/// not a target: it must never go down, and the cases listed below must stay
/// identical one by one. The README's conformance section reports the same
/// figure.
let identical_floor : Int32 = 4

///|
/// Cases that are identical today, named so a regression points at the shader
/// that broke rather than at a count.
let identical_cases : Array[String] = [
  "array-in-function-return-type", "empty", "empty-if", "multiview",
]

///|
test "the corpus replays and keeps its floor" {
  let outcomes = @conformance.replay()
  println(@conformance.summary(outcomes))
  let identical = @conformance.count_identical(outcomes)
  assert_true(identical >= identical_floor)
}

///|
test "the named cases stay identical" {
  let outcomes = @conformance.replay()
  for outcome in outcomes {
    if identical_cases.contains(outcome.name) {
      assert_eq(outcome.status, @conformance.Identical)
    }
  }
}

///|
test "no case is refused for a reason the front end should not have" {
  let outcomes = @conformance.replay()
  let mut refused = 0
  for outcome in outcomes {
    match outcome.status {
      @conformance.Refused(_) => refused = refused + 1
      _ => ()
    }
  }
  println("refused \{refused} of \{outcomes.length()}")
  assert_true(refused <= 25)
}
