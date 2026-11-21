// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Names an identifier uniquely within a module: the first use of a name keeps
/// it, and each collision gets a numeric suffix, which is what keeps two
/// same-named locals of different functions apart once they are written into one
/// file.
pub(all) struct Namer {
  taken : Map[String, Int32]
}

///|
pub fn Namer::new() -> Namer {
  { taken: Map([]), }
}

///|
pub fn Namer::reserve(self : Namer, name : String) -> Unit {
  self.taken[name] = 1
}

///|
pub fn Namer::unique(self : Namer, base : String) -> String {
  let stem = sanitize(base)
  match self.taken.get(stem) {
    None => {
      self.taken[stem] = 1
      stem
    }
    Some(count) => {
      let mut next = count
      while true {
        let candidate = stem + "_" + next.to_string()
        match self.taken.get(candidate) {
          None => {
            self.taken[candidate] = 1
            self.taken[stem] = next + 1
            return candidate
          }
          Some(_) => next = next + 1
        }
      }
      stem
    }
  }
}

///|
/// Keeps the characters WGSL allows in an identifier and replaces the rest, so a
/// name that came from somewhere else still writes as valid source.
fn sanitize(name : String) -> String {
  if name.is_empty() {
    return "_"
  }
  let chars = name.to_array()
  let builder = StringBuilder()
  for index in 0..<chars.length() {
    let ch = chars[index]
    let keep = (ch.is_ascii_alphabetic() || ch.is_ascii_digit()) ||
      ch == '_' ||
      ch.to_int() >= 0x80
    if keep {
      builder.write_char(ch)
    } else {
      builder.write_char('_')
    }
  }
  let text = builder.to_string()
  let first = text.to_array()[0]
  if first.is_ascii_digit() {
    "_" + text
  } else {
    text
  }
}
