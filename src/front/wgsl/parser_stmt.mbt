// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn Parser::parse_block(self : Parser) -> Array[Stmt] raise Failed {
  ignore(self.expect_punct(BraceLeft))
  let stmts = []
  while !self.at_punct(BraceRight) && !self.at_eof() {
    stmts.push(self.parse_stmt())
  }
  ignore(self.expect_punct(BraceRight))
  stmts
}

///|
fn Parser::parse_stmt(self : Parser) -> Stmt raise Failed {
  if self.at_punct(BraceLeft) {
    return SBlock(self.parse_block())
  }
  if self.at_punct(Semicolon) {
    ignore(self.advance())
    return SEmpty
  }
  match self.peek_kind() {
    Ident(word) =>
      match word {
        "if" => self.parse_if()
        "loop" => self.parse_loop()
        "for" => self.parse_for()
        "while" => self.parse_while()
        "switch" => self.parse_switch()
        "break" => {
          let span = self.peek_span()
          ignore(self.advance())
          ignore(self.expect_punct(Semicolon))
          SBreak(span)
        }
        "continue" => {
          let span = self.peek_span()
          ignore(self.advance())
          ignore(self.expect_punct(Semicolon))
          SContinue(span)
        }
        "return" => {
          ignore(self.advance())
          let value = if self.at_punct(Semicolon) {
            None
          } else {
            Some(self.parse_expr())
          }
          ignore(self.expect_punct(Semicolon))
          SReturn(value)
        }
        "discard" => {
          let span = self.peek_span()
          ignore(self.advance())
          ignore(self.expect_punct(Semicolon))
          SDiscard(span)
        }
        "let" => self.parse_let()
        "var" => self.parse_local_var()
        "const" => self.parse_local_const()
        "const_assert" => {
          ignore(self.advance())
          let expr = self.parse_expr()
          ignore(self.expect_punct(Semicolon))
          SConstAssert(expr, self.peek_span())
        }
        _ => self.parse_expr_stmt()
      }
    _ => self.parse_expr_stmt()
  }
}

///|
fn Parser::parse_expr_stmt(self : Parser) -> Stmt raise Failed {
  let expr = self.parse_expr()
  let span = expr_span(expr)
  match self.peek_kind() {
    Punct(Equal) => {
      ignore(self.advance())
      let value = self.parse_expr()
      ignore(self.expect_punct(Semicolon))
      SAssign(expr, AssignOp::Assign, value, span)
    }
    Punct(PlusEqual) => self.parse_compound(expr, Add, span)
    Punct(MinusEqual) => self.parse_compound(expr, Subtract, span)
    Punct(StarEqual) => self.parse_compound(expr, Multiply, span)
    Punct(SlashEqual) => self.parse_compound(expr, Divide, span)
    Punct(PercentEqual) => self.parse_compound(expr, Modulo, span)
    Punct(AndEqual) => self.parse_compound(expr, And, span)
    Punct(OrEqual) => self.parse_compound(expr, Or, span)
    Punct(XorEqual) => self.parse_compound(expr, Xor, span)
    Punct(ShiftLeftEqual) => self.parse_compound(expr, ShiftLeft, span)
    Punct(ShiftRightEqual) => self.parse_compound(expr, ShiftRight, span)
    Punct(Increment) => {
      ignore(self.advance())
      ignore(self.expect_punct(Semicolon))
      SIncrement(expr, 1, span)
    }
    Punct(Decrement) => {
      ignore(self.advance())
      ignore(self.expect_punct(Semicolon))
      SIncrement(expr, -1, span)
    }
    _ => {
      ignore(self.expect_punct(Semicolon))
      SExpr(expr)
    }
  }
}

///|
fn Parser::parse_compound(
  self : Parser,
  target : Expr,
  op : AssignOp,
  span : @moonnaga.Span,
) -> Stmt raise Failed {
  ignore(self.advance())
  let value = self.parse_expr()
  ignore(self.expect_punct(Semicolon))
  SAssign(target, op, value, span)
}

///|
fn Parser::parse_let(self : Parser) -> Stmt raise Failed {
  let span = self.peek_span()
  ignore(self.advance())
  let (name, _) = self.expect_ident()
  let mut ty = None
  if self.eat_punct(Colon) {
    ty = Some(self.parse_type())
  }
  let mut init = None
  if self.eat_punct(Equal) {
    init = Some(self.parse_expr())
  }
  ignore(self.expect_punct(Semicolon))
  SLet(name, ty, init, [], span)
}

///|
fn Parser::parse_local_var(self : Parser) -> Stmt raise Failed {
  let span = self.peek_span()
  ignore(self.advance())
  let space = self.parse_address_space()
  let (name, _) = self.expect_ident()
  let mut ty = None
  if self.eat_punct(Colon) {
    ty = Some(self.parse_type())
  }
  let mut init = None
  if self.eat_punct(Equal) {
    init = Some(self.parse_expr())
  }
  ignore(self.expect_punct(Semicolon))
  SVar(name, ty, init, [], space, span)
}

///|
fn Parser::parse_local_const(self : Parser) -> Stmt raise Failed {
  let span = self.peek_span()
  ignore(self.advance())
  let (name, _) = self.expect_ident()
  let mut ty = None
  if self.eat_punct(Colon) {
    ty = Some(self.parse_type())
  }
  ignore(self.expect_punct(Equal))
  let init = self.parse_expr()
  ignore(self.expect_punct(Semicolon))
  SConst(name, ty, init, span)
}

///|
fn Parser::parse_if(self : Parser) -> Stmt raise Failed {
  ignore(self.advance())
  let condition = self.parse_condition()
  let accept = self.parse_block()
  let mut reject = []
  if self.eat_word("else") {
    if self.at_word("if") {
      reject = [self.parse_if()]
    } else {
      reject = self.parse_block()
    }
  }
  SIf(condition, accept, reject)
}

///|
fn Parser::parse_loop(self : Parser) -> Stmt raise Failed {
  ignore(self.advance())
  ignore(self.expect_punct(BraceLeft))
  let body = []
  let continuing = []
  let mut break_if = None
  while !self.at_punct(BraceRight) && !self.at_eof() {
    if self.at_word("continuing") {
      ignore(self.advance())
      ignore(self.expect_punct(BraceLeft))
      while !self.at_punct(BraceRight) && !self.at_eof() {
        if self.at_word("break") && self.at_word_at(1, "if") {
          ignore(self.advance())
          ignore(self.advance())
          break_if = Some(self.parse_expr())
          ignore(self.expect_punct(Semicolon))
        } else {
          continuing.push(self.parse_stmt())
        }
      }
      ignore(self.expect_punct(BraceRight))
    } else {
      body.push(self.parse_stmt())
    }
  }
  ignore(self.expect_punct(BraceRight))
  SLoop(body, continuing, break_if)
}

///|
fn Parser::at_word_at(self : Parser, offset : Int32, word : String) -> Bool {
  let index = self.pos.to_int() + offset.to_int()
  if index >= self.tokens.length() {
    return false
  }
  match self.tokens[index].kind {
    Ident(name) => name == word
    _ => false
  }
}

///|
fn Parser::parse_for(self : Parser) -> Stmt raise Failed {
  ignore(self.advance())
  ignore(self.expect_punct(ParenLeft))
  let init = if self.at_punct(Semicolon) {
    None
  } else {
    // A declaration consumes its own `;`; an expression clause does not.
    let clause = self.parse_for_clause()
    ignore(self.eat_punct(Semicolon))
    Some(clause)
  }
  ignore(self.expect_punct(Semicolon))
  let condition = if self.at_punct(Semicolon) {
    None
  } else {
    Some(self.parse_expr())
  }
  ignore(self.expect_punct(Semicolon))
  let update = if self.at_punct(ParenRight) {
    None
  } else {
    Some(self.parse_for_clause())
  }
  ignore(self.expect_punct(ParenRight))
  let body = self.parse_block()
  SFor({ init, condition, update, body, })
}

///|
/// The initialiser or the update of a `for`: a declaration or an expression
/// statement, without the `;` the surrounding parens already delimit.
fn Parser::parse_for_clause(self : Parser) -> Stmt raise Failed {
  if self.at_word("var") {
    return self.parse_local_var()
  }
  if self.at_word("let") {
    return self.parse_let()
  }
  let expr = self.parse_expr()
  let span = expr_span(expr)
  match self.peek_kind() {
    Punct(Equal) => {
      ignore(self.advance())
      let value = self.parse_expr()
      SAssign(expr, AssignOp::Assign, value, span)
    }
    Punct(PlusEqual) => self.parse_for_compound(expr, Add, span)
    Punct(MinusEqual) => self.parse_for_compound(expr, Subtract, span)
    Punct(StarEqual) => self.parse_for_compound(expr, Multiply, span)
    Punct(SlashEqual) => self.parse_for_compound(expr, Divide, span)
    Punct(PercentEqual) => self.parse_for_compound(expr, Modulo, span)
    Punct(Increment) => {
      ignore(self.advance())
      SIncrement(expr, 1, span)
    }
    Punct(Decrement) => {
      ignore(self.advance())
      SIncrement(expr, -1, span)
    }
    _ => SExpr(expr)
  }
}

///|
fn Parser::parse_for_compound(
  self : Parser,
  target : Expr,
  op : AssignOp,
  span : @moonnaga.Span,
) -> Stmt raise Failed {
  ignore(self.advance())
  let value = self.parse_expr()
  SAssign(target, op, value, span)
}

///|
fn Parser::parse_while(self : Parser) -> Stmt raise Failed {
  ignore(self.advance())
  let condition = self.parse_condition()
  let body = self.parse_block()
  SWhile(condition, body)
}

///|
fn Parser::parse_switch(self : Parser) -> Stmt raise Failed {
  ignore(self.advance())
  let selector = self.parse_condition()
  ignore(self.expect_punct(BraceLeft))
  let arms = []
  while !self.at_punct(BraceRight) && !self.at_eof() {
    if self.eat_word("default") {
      ignore(self.expect_punct(Colon))
      let body = self.parse_case_body()
      arms.push({ value: None, body, })
    } else {
      self.expect_word("case")
      let value = self.parse_expr()
      ignore(self.expect_punct(Colon))
      let body = self.parse_case_body()
      arms.push({ value: Some(value), body, })
    }
  }
  ignore(self.expect_punct(BraceRight))
  SSwitch(selector, arms)
}

///|
/// The statements of one `case`: either a braced block or everything up to the
/// next `case`, `default` or closing brace.
fn Parser::parse_case_body(self : Parser) -> Array[Stmt] raise Failed {
  if self.at_punct(BraceLeft) {
    return self.parse_block()
  }
  let body = []
  while !self.at_punct(BraceRight) &&
        !self.at_word("case") &&
        !self.at_word("default") &&
        !self.at_eof() {
    body.push(self.parse_stmt())
  }
  body
}

///|
/// The condition of `if`, `while` and `switch`: the grammar accepts it with or
/// without parentheses, and both spellings appear in the wild.
fn Parser::parse_condition(self : Parser) -> Expr raise Failed {
  if self.at_punct(ParenLeft) {
    ignore(self.advance())
    let inner = self.parse_expr()
    ignore(self.expect_punct(ParenRight))
    inner
  } else {
    self.parse_expr()
  }
}
