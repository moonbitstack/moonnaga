// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads the digits of an integer literal.
///
/// The text is what the lexer saw, so it may carry a `0x` prefix; the value is
/// computed rather than parsed by a library because the core parser is internal
/// to the standard library and this front end has no other dependency.
fn integer_of_text(
  text : String,
  span : @moonnaga.Span,
  radix : Int32,
) -> Int64 raise Failed {
  let digits = text.to_array()
  let mut index = 0
  let mut base = radix
  if text.has_prefix("0x") || text.has_prefix("0X") {
    base = 16
    index = 2
  } else if base == 0 {
    base = 10
  }
  if index >= digits.length() {
    return fail("`\{text}` is not an integer", span)
  }
  let mut value : Int64 = 0
  while index < digits.length() {
    let digit = digit_value(digits[index])
    if digit < 0 || digit >= base {
      return fail("`\{text}` is not an integer", span)
    }
    value = value * base.to_int64() + digit.to_int64()
    index = index + 1
  }
  value
}

///|
fn digit_value(ch : Char) -> Int32 {
  if ch >= '0' && ch <= '9' {
    ch.to_int() - '0'.to_int()
  } else if ch >= 'a' && ch <= 'f' {
    ch.to_int() - 'a'.to_int() + 10
  } else if ch >= 'A' && ch <= 'F' {
    ch.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// Reads a floating-point literal.
///
/// The mantissa is accumulated as an integer and then scaled by a power of ten,
/// which keeps every digit the source wrote; the result is the nearest double
/// the arithmetic can reach, and the writers print it back with the shortest
/// text that round-trips.
fn float_of_text(text : String, span : @moonnaga.Span) -> Double raise Failed {
  let digits = text.to_array()
  let count = digits.length()
  let mut index = 0
  let mut mantissa : Int64 = 0
  let mut exponent : Int32 = 0
  let mut seen_digit = false
  while index < count && digits[index] >= '0' && digits[index] <= '9' {
    mantissa = mantissa * 10 +
      (digits[index].to_int() - '0'.to_int()).to_int64()
    seen_digit = true
    index = index + 1
  }
  if index < count && digits[index] == '.' {
    index = index + 1
    while index < count && digits[index] >= '0' && digits[index] <= '9' {
      mantissa = mantissa * 10 +
        (digits[index].to_int() - '0'.to_int()).to_int64()
      exponent = exponent - 1
      seen_digit = true
      index = index + 1
    }
  }
  if !seen_digit {
    return fail("`\{text}` is not a number", span)
  }
  if index < count && (digits[index] == 'e' || digits[index] == 'E') {
    index = index + 1
    let mut negative = false
    if index < count && (digits[index] == '+' || digits[index] == '-') {
      negative = digits[index] == '-'
      index = index + 1
    }
    let mut magnitude : Int32 = 0
    let mut seen_exponent = false
    while index < count && digits[index] >= '0' && digits[index] <= '9' {
      magnitude = magnitude * 10 + (digits[index].to_int() - '0'.to_int())
      seen_exponent = true
      index = index + 1
    }
    if !seen_exponent {
      return fail("`\{text}` is not a number", span)
    }
    exponent = if negative {
      exponent - magnitude
    } else {
      exponent + magnitude
    }
  }
  if index != count {
    return fail("`\{text}` is not a number", span)
  }
  let mut value = mantissa.to_double()
  if exponent > 0 {
    for _ in 0..<exponent {
      value = value * 10.0
    }
  } else if exponent < 0 {
    for _ in 0..<-exponent {
      value = value / 10.0
    }
  }
  value
}
