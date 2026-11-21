// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where the parser stopped after the last token it consumed, which is the end
/// of the expression it just read.
fn Parser::previous_end(self : Parser) -> Int32 {
  let index = self.pos.to_int()
  if index == 0 {
    0
  } else {
    self.tokens[index - 1].span.end
  }
}

///|
fn Parser::parse_expr(self : Parser) -> Expr raise Failed {
  self.parse_binary(0)
}

///|
/// The binding power of a binary operator, or `None` when the token is not one.
fn binary_power(punct : Punct) -> (Int32, BinaryOp)? {
  match punct {
    LogicalOr => Some((1, LogicalOr))
    LogicalAnd => Some((2, LogicalAnd))
    Or => Some((3, Or))
    Xor => Some((4, Xor))
    And => Some((5, And))
    EqualEqual => Some((6, Equal))
    NotEqual => Some((6, NotEqual))
    Less => Some((7, Less))
    LessEqual => Some((7, LessEqual))
    Greater => Some((7, Greater))
    GreaterEqual => Some((7, GreaterEqual))
    ShiftLeft => Some((8, ShiftLeft))
    ShiftRight => Some((8, ShiftRight))
    Plus => Some((9, Add))
    Minus => Some((9, Subtract))
    Star => Some((10, Multiply))
    Slash => Some((10, Divide))
    Percent => Some((10, Modulo))
    _ => None
  }
}

///|
fn Parser::parse_binary(self : Parser, min_power : Int32) -> Expr raise Failed {
  let mut left = self.parse_unary()
  while true {
    let step = match self.peek_kind() {
      Punct(Greater) =>
        if self.in_template {
          None
        } else {
          binary_power(Greater)
        }
      Punct(GreaterEqual) =>
        if self.in_template {
          None
        } else {
          binary_power(GreaterEqual)
        }
      Punct(punct) => binary_power(punct)
      _ => None
    }
    match step {
      Some((power, op)) => {
        if power < min_power {
          break
        }
        let start = expr_span(left).start
        ignore(self.advance())
        let right = self.parse_binary(power + 1)
        left = BinaryApply(
          op,
          left,
          right,
          @moonnaga.Span::new(start, expr_span(right).end),
        )
      }
      None => break
    }
  }
  left
}

///|
fn Parser::parse_unary(self : Parser) -> Expr raise Failed {
  let span = self.peek_span()
  let op = match self.peek_kind() {
    Punct(Minus) => Some(Negate)
    Punct(Not) => Some(LogicalNot)
    Punct(Tilde) => Some(BitwiseNot)
    Punct(Star) => Some(Deref)
    Punct(And) => Some(AddressOf)
    _ => None
  }
  match op {
    Some(op) => {
      ignore(self.advance())
      let operand = self.parse_unary()
      UnaryApply(
        op,
        operand,
        @moonnaga.Span::new(span.start, expr_span(operand).end),
      )
    }
    None => self.parse_postfix()
  }
}

///|
fn Parser::parse_postfix(self : Parser) -> Expr raise Failed {
  let mut expr = self.parse_primary()
  while true {
    if self.at_punct(Dot) {
      ignore(self.advance())
      let (name, name_span) = self.expect_ident()
      expr = Member(expr, name, {
        start: expr_span(expr).start,
        end: name_span.end,
      })
    } else if self.at_punct(BracketLeft) {
      let start = expr_span(expr).start
      ignore(self.advance())
      let index = self.parse_expr()
      let close = self.expect_punct(BracketRight)
      expr = Index(expr, index, @moonnaga.Span::new(start, close.end))
    } else {
      break
    }
  }
  expr
}

///|
fn Parser::parse_primary(self : Parser) -> Expr raise Failed {
  let token = self.peek()
  match token.kind {
    Number(number) => {
      ignore(self.advance())
      Number(number, token.span)
    }
    Ident(name) => {
      ignore(self.advance())
      if name == "true" || name == "false" {
        return Bool(name == "true", token.span)
      }
      let mut args = []
      let next = self.peek_span()
      if self.at_punct(Less) && token.span.end == next.start {
        ignore(self.advance())
        args = self.parse_template_args(name)
        self.expect_greater()
        ignore(self.expect_punct(ParenLeft))
        let call_args = self.parse_call_args()
        return Invoke(name, args, call_args, {
          start: token.span.start,
          end: self.previous_end(),
        })
      }
      if self.at_punct(ParenLeft) {
        ignore(self.advance())
        let call_args = self.parse_call_args()
        return Invoke(name, args, call_args, {
          start: token.span.start,
          end: self.previous_end(),
        })
      }
      Ident(name, token.span)
    }
    Punct(ParenLeft) => {
      ignore(self.advance())
      let inner = self.parse_expr()
      ignore(self.expect_punct(ParenRight))
      inner
    }
    _ => fail("expected an expression", token.span)
  }
}

///|
/// The argument list of a call, with its closing `)` already consumed.
fn Parser::parse_call_args(self : Parser) -> Array[Expr] raise Failed {
  let args = []
  while !self.at_punct(ParenRight) {
    args.push(self.parse_expr())
    if !self.eat_punct(Comma) {
      break
    }
  }
  ignore(self.expect_punct(ParenRight))
  args
}

///|
pub fn expr_span(expr : Expr) -> @moonnaga.Span {
  match expr {
    Number(_, span) | Bool(_, span) | Ident(_, span) => span
    UnaryApply(_, _, span) => span
    BinaryApply(_, _, _, span) => span
    Invoke(_, _, _, span) => span
    Bitcast(_, _, span) => span
    Index(_, _, span) => span
    Member(_, _, span) => span
  }
}
