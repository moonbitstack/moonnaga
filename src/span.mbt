// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A half-open byte range into the source text. The offsets are bytes rather
/// than characters because that is what the lexer tracks, and diagnostics
/// convert them to a line and a column on the way out.
#derive(Eq, Debug)
pub(all) struct Span {
  start : Int32
  end : Int32
}

///|
pub fn Span::new(start : Int32, end : Int32) -> Span {
  { start, end, }
}

///|
/// A position in the source text, counting from one, as a reader sees it.
#derive(Eq, Debug)
pub(all) struct SourceLocation {
  line : Int32
  column : Int32
}

///|
pub fn location_of(text : StringView, offset : Int32) -> SourceLocation {
  let limit = if offset < 0 { 0 } else { offset }
  let bytes = text.to_owned()
  let end = if limit > bytes.length() { bytes.length() } else { limit }
  let mut line = 1
  let mut column = 1
  let mut index = 0
  // A column is measured in scalar values, not in bytes, so a source file with
  // non-ASCII identifiers reports the position a reader would point at.
  let chars = bytes.to_array()
  while index < end {
    let byte = chars[index].to_int()
    if byte == 0x0A {
      line = line + 1
      column = 1
      index = index + 1
    } else if byte < 0x80 {
      column = column + 1
      index = index + 1
    } else {
      let width = if byte >= 0xF0 {
        4
      } else if byte >= 0xE0 {
        3
      } else if byte >= 0xC0 {
        2
      } else {
        1
      }
      column = column + 1
      index = index + width
    }
  }
  { line, column, }
}
