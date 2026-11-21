// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The punctuation the grammar distinguishes. Multi-character operators are
/// single tokens here; the template lists of the type grammar are the one place
/// where the parser has to split a token, which it does when it meets `>>`.
#derive(Eq, Hash, Debug)
pub(all) enum Punct {
  Arrow
  Comma
  Dot
  Semicolon
  Colon
  ParenLeft
  ParenRight
  BracketLeft
  BracketRight
  BraceLeft
  BraceRight
  At
  Plus
  Minus
  Star
  Slash
  Percent
  And
  Or
  Xor
  Not
  Tilde
  ShiftLeft
  ShiftRight
  Equal
  EqualEqual
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
  LogicalAnd
  LogicalOr
  PlusEqual
  MinusEqual
  StarEqual
  SlashEqual
  PercentEqual
  AndEqual
  OrEqual
  XorEqual
  ShiftLeftEqual
  ShiftRightEqual
  Increment
  Decrement
}

///|
/// The suffix a numeric literal carries, which is what fixes its type.
#derive(Eq, Debug)
pub(all) enum NumberSuffix {
  Plain
  Signed
  Unsigned
  Float
  Half
  /// `lf`, a 64-bit float, which an extension enables.
  DoubleSuffix
  /// `li`, a 64-bit signed integer.
  LongSigned
  /// `lu`, a 64-bit unsigned integer.
  LongUnsigned
  /// `lh`, a 64-bit half float.
  DoubleHalf
}

///|
/// A numeric literal, kept as text as well as parsed: the abstract types of WGSL
/// have to remember whether the source said `1`, `1.0` or `0x1`, and the writers
/// reproduce the spelling the round trip started from.
#derive(Eq, Debug)
pub(all) struct NumberLit {
  text : String
  is_float : Bool
  suffix : NumberSuffix
}

///|
#derive(Eq, Debug)
pub(all) enum TokenKind {
  Ident(String)
  Number(NumberLit)
  Punct(Punct)
  Eof
}

///|
#derive(Eq, Debug)
pub(all) struct Token {
  kind : TokenKind
  span : @moonnaga.Span
}

///|
/// Splits source text into tokens.
///
/// Comments and whitespace disappear here; everything else reaches the parser,
/// which is what makes the parser readable as a transcription of the grammar.
pub fn tokenize(text : StringView) -> Array[Token] raise Failed {
  let chars = text.to_owned().to_array()
  let count = chars.length()
  let tokens = []
  let mut index = 0
  while index < count {
    let start = index
    let ch = chars[index]
    if ch.is_whitespace() {
      index = index + 1
      continue
    }
    // A byte order mark is legal at the start of a source file and nowhere
    // else, but tolerating it anywhere costs nothing and spares a slow failure.
    if ch.to_int() == 0xFEFF {
      index = index + 1
      continue
    }
    if ch == '/' && index + 1 < count && chars[index + 1] == '/' {
      while index < count && chars[index] != '\n' {
        index = index + 1
      }
      continue
    }
    if ch == '/' && index + 1 < count && chars[index + 1] == '*' {
      index = index + 2
      let mut depth = 1
      while index < count && depth > 0 {
        if chars[index] == '*' && index + 1 < count && chars[index + 1] == '/' {
          depth = depth - 1
          index = index + 2
        } else if chars[index] == '/' &&
          index + 1 < count &&
          chars[index + 1] == '*' {
          depth = depth + 1
          index = index + 2
        } else {
          index = index + 1
        }
      }
      if depth > 0 {
        fail("an unterminated block comment", { start, end: count, })
      }
      continue
    }
    if is_ident_start(ch) {
      index = index + 1
      while index < count && is_ident_continue(chars[index]) {
        index = index + 1
      }
      let name = String::from_array(chars[start:index])
      tokens.push({ kind: Ident(name), span: { start, end: index, }, })
      continue
    }
    if ch.is_ascii_digit() ||
      (ch == '.' && index + 1 < count && chars[index + 1].is_ascii_digit()) {
      let (next, number) = lex_number(chars, index)
      index = next
      tokens.push({ kind: Number(number), span: { start, end: index, }, })
      continue
    }
    let (next, punct) = lex_punct(chars, index)
    if next == index {
      fail("unexpected character \{ch}", { start, end: index + 1, })
    }
    index = next
    tokens.push({ kind: Punct(punct), span: { start, end: index, }, })
  }
  tokens.push({ kind: Eof, span: { start: count, end: count, }, })
  tokens
}

///|
/// WGSL identifiers are XID_Start followed by XID_Continue. The classification
/// tables are not in this library's dependency set, so the test is the one a
/// graphic shader needs: ASCII letters, digits, `_`, and any code point above
/// ASCII, which covers the non-Latin identifiers the specification allows.
fn is_ident_start(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || ch == '_' || ch.to_int() >= 0x80
}

///|
fn is_ident_continue(ch : Char) -> Bool {
  is_ident_start(ch) || ch.is_ascii_digit()
}

///|
/// Reads a numeric literal and returns where it ends.
fn lex_number(
  chars : Array[Char],
  start : Int32,
) -> (Int32, NumberLit) raise Failed {
  let count = chars.length()
  let mut index = start
  let mut is_float = false
  if chars[index] == '0' &&
    index + 1 < count &&
    (chars[index + 1] == 'x' || chars[index + 1] == 'X') {
    index = index + 2
    let digits_start = index
    while index < count && chars[index].is_ascii_hexdigit() {
      index = index + 1
    }
    if index == digits_start {
      fail("a hexadecimal literal without digits", { start, end: index, })
    }
    let (end, suffix) = lex_suffix(chars, index, true)
    let digit_end = index
    return (
      end,
      {
        text: String::from_array(chars[start:digit_end]),
        is_float: false,
        suffix,
      },
    )
  }
  while index < count && chars[index].is_ascii_digit() {
    index = index + 1
  }
  if index < count && chars[index] == '.' {
    is_float = true
    index = index + 1
    while index < count && chars[index].is_ascii_digit() {
      index = index + 1
    }
  }
  if index < count && (chars[index] == 'e' || chars[index] == 'E') {
    is_float = true
    index = index + 1
    if index < count && (chars[index] == '+' || chars[index] == '-') {
      index = index + 1
    }
    while index < count && chars[index].is_ascii_digit() {
      index = index + 1
    }
  }
  let text_end = index
  let (end, suffix) = lex_suffix(chars, index, false)
  (end, { text: String::from_array(chars[start:text_end]), is_float, suffix, })
}

///|
fn lex_suffix(
  chars : Array[Char],
  start : Int32,
  hex : Bool,
) -> (Int32, NumberSuffix) {
  if start >= chars.length() {
    return (start, Plain)
  }
  // The 64-bit suffixes are two letters: `li`, `lu`, `lf`, `lh`.
  if chars[start] == 'l' && start + 1 < chars.length() {
    match chars[start + 1] {
      'i' => return (start + 2, LongSigned)
      'u' => return (start + 2, LongUnsigned)
      'f' => return (start + 2, DoubleSuffix)
      'h' => return (start + 2, DoubleHalf)
      _ => ()
    }
  }
  match chars[start] {
    'i' => (start + 1, Signed)
    'u' => (start + 1, Unsigned)
    'f' => (start + 1, Float)
    'h' => (start + 1, Half)
    // `e` opens an exponent in a decimal literal, so it is a suffix only after
    // a hexadecimal one, where no exponent follows.
    'e' if hex => (start + 1, Plain)
    _ => (start, Plain)
  }
}

///|
fn lex_punct(chars : Array[Char], start : Int32) -> (Int32, Punct) {
  let count = chars.length()
  let at = fn(offset : Int32) -> Char {
    if start + offset < count {
      chars[start + offset]
    } else {
      '\u{0}'
    }
  }
  let c0 = at(0)
  let c1 = at(1)
  let c2 = at(2)
  match (c0, c1, c2) {
    ('-', '>', _) => (start + 2, Arrow)
    ('=', '=', _) => (start + 2, EqualEqual)
    ('!', '=', _) => (start + 2, NotEqual)
    ('<', '=', _) => (start + 2, LessEqual)
    ('>', '=', _) => (start + 2, GreaterEqual)
    ('&', '&', _) => (start + 2, LogicalAnd)
    ('|', '|', _) => (start + 2, LogicalOr)
    ('+', '+', _) => (start + 2, Increment)
    ('-', '-', _) => (start + 2, Decrement)
    ('+', '=', _) => (start + 2, PlusEqual)
    ('-', '=', _) => (start + 2, MinusEqual)
    ('*', '=', _) => (start + 2, StarEqual)
    ('/', '=', _) => (start + 2, SlashEqual)
    ('%', '=', _) => (start + 2, PercentEqual)
    ('&', '=', _) => (start + 2, AndEqual)
    ('|', '=', _) => (start + 2, OrEqual)
    ('^', '=', _) => (start + 2, XorEqual)
    ('<', '<', '=') => (start + 3, ShiftLeftEqual)
    ('>', '>', '=') => (start + 3, ShiftRightEqual)
    ('<', '<', _) => (start + 2, ShiftLeft)
    ('>', '>', _) => (start + 2, ShiftRight)
    (',', _, _) => (start + 1, Comma)
    ('.', _, _) => (start + 1, Dot)
    (';', _, _) => (start + 1, Semicolon)
    (':', _, _) => (start + 1, Colon)
    ('(', _, _) => (start + 1, ParenLeft)
    (')', _, _) => (start + 1, ParenRight)
    ('[', _, _) => (start + 1, BracketLeft)
    (']', _, _) => (start + 1, BracketRight)
    ('{', _, _) => (start + 1, BraceLeft)
    ('}', _, _) => (start + 1, BraceRight)
    ('@', _, _) => (start + 1, At)
    ('+', _, _) => (start + 1, Plus)
    ('-', _, _) => (start + 1, Minus)
    ('*', _, _) => (start + 1, Star)
    ('/', _, _) => (start + 1, Slash)
    ('%', _, _) => (start + 1, Percent)
    ('&', _, _) => (start + 1, And)
    ('|', _, _) => (start + 1, Or)
    ('^', _, _) => (start + 1, Xor)
    ('!', _, _) => (start + 1, Not)
    ('~', _, _) => (start + 1, Tilde)
    ('=', _, _) => (start + 1, Equal)
    ('<', _, _) => (start + 1, Less)
    ('>', _, _) => (start + 1, Greater)
    _ => (start, Comma)
  }
}
