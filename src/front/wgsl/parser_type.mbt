// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads a type.
///
/// A template list is written with no space between the name and the `<`; that
/// adjacency is what tells `vec4<f32>` from the comparison `a<b` in an
/// expression, and the grammar relies on it too.
fn Parser::parse_type(self : Parser) -> TypeExpr raise Failed {
  if self.at_word("ptr") {
    return self.parse_pointer_type()
  }
  let token = self.peek()
  let (name, span) = self.expect_ident()
  let mut args = []
  let next = self.peek_span()
  if self.at_punct(Less) && token.span.end == next.start {
    ignore(self.advance())
    args = self.parse_template_args(name)
    self.expect_greater()
  }
  Named(name, args, span)
}

///|
fn Parser::parse_pointer_type(self : Parser) -> TypeExpr raise Failed {
  let span = self.peek_span()
  ignore(self.advance())
  ignore(self.expect_punct(Less))
  let (space, _) = self.expect_ident()
  ignore(self.expect_punct(Comma))
  let base = self.parse_type()
  let mut access = None
  if self.eat_punct(Comma) {
    let (word, _) = self.expect_ident()
    access = Some(word)
  }
  self.expect_greater()
  Pointer({ space, base, access, span, })
}

///|
/// The arguments of a template list. `array` and `binding_array` take a type and
/// then an expression; every other name takes types only.
fn Parser::parse_template_args(
  self : Parser,
  name : String,
) -> Array[TemplateArg] raise Failed {
  let args = []
  if name == "array" || name == "binding_array" {
    args.push(Type(self.parse_type()))
    if self.eat_punct(Comma) {
      let saved = self.in_template
      self.in_template = true
      let size = self.parse_expr()
      self.in_template = saved
      args.push(Expr(size))
    }
  } else {
    while true {
      args.push(Type(self.parse_type()))
      if !self.eat_punct(Comma) {
        break
      }
    }
  }
  args
}
