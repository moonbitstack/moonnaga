// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How one replayed case came out.
#derive(Eq, Debug)
pub(all) enum Status {
  /// The text this library wrote is the text recorded from naga's writer.
  Identical
  /// The source did not parse, with the diagnostic it reported.
  Refused(String)
  /// The source parsed and wrote back, but the text differs.
  Differed
}

///|
#derive(Debug)
pub(all) struct Outcome {
  name : String
  status : Status
}

///|
/// Replays every case of the corpus.
pub fn replay() -> Array[Outcome] {
  let outcomes = []
  for entry in @corpus.cases() {
    let (name, source, expected) = entry
    let status = match @front.parse(source) {
      Ok(shader) => {
        let text = @writer.write_module(shader)
        if text == expected {
          Identical
        } else {
          Differed
        }
      }
      Err(error) =>
        Refused(
          error.message +
          " (line " +
          error.line.to_string() +
          ", column " +
          error.column.to_string() +
          ")",
        )
    }
    outcomes.push({ name, status, })
  }
  outcomes
}

///|
/// How many cases came out byte for byte identical.
pub fn count_identical(outcomes : Array[Outcome]) -> Int32 {
  let mut count = 0
  for outcome in outcomes {
    if outcome.status == Identical {
      count = count + 1
    }
  }
  count
}

///|
/// The names of the cases that did not come out identical, grouped by why.
pub fn summary(outcomes : Array[Outcome]) -> String {
  let builder = StringBuilder()
  let mut identical = 0
  let mut refused = 0
  let mut differed = 0
  for outcome in outcomes {
    match outcome.status {
      Identical => identical = identical + 1
      Refused(_) => refused = refused + 1
      Differed => differed = differed + 1
    }
  }
  builder.write_string(
    "identical " +
    identical.to_string() +
    " of " +
    outcomes.length().to_string() +
    " (refused " +
    refused.to_string() +
    ", differed " +
    differed.to_string() +
    ")",
  )
  builder.to_string()
}
