// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A diagnostic tied to a range of the source text. The line and the column are
/// filled in when the diagnostic is raised, not when it is created, so a caller
/// that only wants the message can ignore them.
#derive(Eq, Debug)
pub(all) struct ParseError {
  message : String
  span : @moonnaga.Span
  line : Int32
  column : Int32
}

///|
/// The way out of the front end when the source does not parse.
pub suberror Failed {
  Failed(ParseError)
}

///|
pub fn[T] fail(message : String, span : @moonnaga.Span) -> T raise Failed {
  raise Failed({ message, span, line: 0, column: 0, })
}
