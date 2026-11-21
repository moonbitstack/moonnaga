// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The parser's whole state: the token stream, the position in it, and the one
/// piece of lookahead the grammar needs.
///
/// `>>` is a single token. Everywhere a template list closes, the parser wants
/// two `>`; splitting the token lazily through `pending_greater` keeps the
/// lexer free of context and the parser free of token rewriting.
pub(all) struct Parser {
  tokens : Array[Token]
  mut pos : Int32
  mut pending_greater : Bool
  /// Set while reading a template argument, where `>` closes the list instead of
  /// comparing.
  mut in_template : Bool
}

///|
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0, pending_greater: false, in_template: false, }
}

///|
fn Parser::peek(self : Parser) -> Token {
  self.tokens[self.pos.to_int()]
}

///|
fn Parser::peek_kind(self : Parser) -> TokenKind {
  if self.pending_greater {
    Punct(Greater)
  } else {
    self.peek().kind
  }
}

///|
fn Parser::peek_span(self : Parser) -> @moonnaga.Span {
  self.peek().span
}

///|
fn Parser::advance(self : Parser) -> Token {
  let token = self.tokens[self.pos.to_int()]
  if self.pos.to_int() + 1 < self.tokens.length() {
    self.pos = self.pos + 1
  }
  token
}

///|
fn Parser::at_punct(self : Parser, punct : Punct) -> Bool {
  match self.peek_kind() {
    Punct(seen) => seen == punct
    _ => false
  }
}

///|
fn Parser::eat_punct(self : Parser, punct : Punct) -> Bool {
  if self.at_punct(punct) {
    if self.pending_greater {
      self.pending_greater = false
    } else {
      ignore(self.advance())
    }
    true
  } else {
    false
  }
}

///|
fn Parser::expect_punct(
  self : Parser,
  punct : Punct,
) -> @moonnaga.Span raise Failed {
  let span = self.peek_span()
  if self.eat_punct(punct) {
    span
  } else {
    fail("expected \{punct_name(punct)}", span)
  }
}

///|
/// Consumes the `>` that closes a template list, splitting a `>>` if that is
/// what the source wrote.
fn Parser::expect_greater(self : Parser) -> Unit raise Failed {
  if self.pending_greater {
    self.pending_greater = false
    return
  }
  match self.peek_kind() {
    Punct(Greater) => ignore(self.advance())
    Punct(ShiftRight) => {
      ignore(self.advance())
      self.pending_greater = true
    }
    _ => fail("expected `>`", self.peek_span())
  }
}

///|
fn Parser::at_word(self : Parser, word : String) -> Bool {
  match self.peek_kind() {
    Ident(name) => name == word
    _ => false
  }
}

///|
fn Parser::eat_word(self : Parser, word : String) -> Bool {
  if self.at_word(word) {
    ignore(self.advance())
    true
  } else {
    false
  }
}

///|
fn Parser::expect_ident(self : Parser) -> (String, @moonnaga.Span) raise Failed {
  let token = self.peek()
  match token.kind {
    Ident(name) => {
      ignore(self.advance())
      (name, token.span)
    }
    _ => fail("expected a name", token.span)
  }
}

///|
fn Parser::expect_word(self : Parser, word : String) -> Unit raise Failed {
  if !self.eat_word(word) {
    fail("expected `\{word}`", self.peek_span())
  }
}

///|
fn Parser::at_eof(self : Parser) -> Bool {
  match self.peek_kind() {
    Eof => true
    _ => false
  }
}

///|
fn punct_name(punct : Punct) -> String {
  match punct {
    Arrow => "->"
    Comma => ","
    Dot => "."
    Semicolon => ";"
    Colon => ":"
    ParenLeft => "("
    ParenRight => ")"
    BracketLeft => "["
    BracketRight => "]"
    BraceLeft => "{"
    BraceRight => "}"
    At => "@"
    Plus => "+"
    Minus => "-"
    Star => "*"
    Slash => "/"
    Percent => "%"
    And => "&"
    Or => "|"
    Xor => "^"
    Not => "!"
    Tilde => "~"
    ShiftLeft => "<<"
    ShiftRight => ">>"
    Equal => "="
    EqualEqual => "=="
    NotEqual => "!="
    Less => "<"
    LessEqual => "<="
    Greater => ">"
    GreaterEqual => ">="
    LogicalAnd => "&&"
    LogicalOr => "||"
    PlusEqual => "+="
    MinusEqual => "-="
    StarEqual => "*="
    SlashEqual => "/="
    PercentEqual => "%="
    AndEqual => "&="
    OrEqual => "|="
    XorEqual => "^="
    ShiftLeftEqual => "<<="
    ShiftRightEqual => ">>="
    Increment => "++"
    Decrement => "--"
  }
}

///|
/// Reads a source file into declarations.
pub fn parse_translation_unit(
  text : StringView,
) -> TranslationUnit raise Failed {
  let tokens = tokenize(text)
  let parser = Parser::new(tokens)
  let decls = []
  while !parser.at_eof() {
    if parser.eat_punct(Semicolon) {
      continue
    }
    let attrs = parser.parse_attributes()
    let (word, span) = parser.expect_ident()
    match word {
      "enable" => {
        let (ext, _) = parser.expect_ident()
        ignore(parser.expect_punct(Semicolon))
        decls.push(Enable(ext))
      }
      "requires" => {
        let (feature, _) = parser.expect_ident()
        ignore(parser.expect_punct(Semicolon))
        decls.push(Requires(feature))
      }
      "diagnostic" => {
        ignore(parser.expect_punct(ParenLeft))
        let (severity, _) = parser.expect_ident()
        let mut rule = None
        if parser.eat_punct(Comma) {
          let (name, _) = parser.expect_ident()
          rule = Some(name)
        }
        ignore(parser.expect_punct(ParenRight))
        ignore(parser.expect_punct(Semicolon))
        decls.push(Diagnostic(severity, rule))
      }
      "const" => decls.push(Const(parser.parse_const_decl(span)))
      "override" =>
        decls.push(Override(parser.parse_override_decl(attrs, span)))
      "var" => decls.push(Var(parser.parse_global_var(attrs, span)))
      "struct" => decls.push(Struct(parser.parse_struct_decl(span)))
      "alias" => {
        let (name, _) = parser.expect_ident()
        ignore(parser.expect_punct(Equal))
        let ty = parser.parse_type()
        ignore(parser.expect_punct(Semicolon))
        decls.push(Alias(name, ty, span))
      }
      "fn" => decls.push(Fn(parser.parse_fn_decl(attrs, span)))
      "const_assert" => {
        let expr = parser.parse_expr()
        ignore(parser.expect_punct(Semicolon))
        decls.push(ConstAssert(expr, span))
      }
      _ => fail("expected a declaration, found `\{word}`", span)
    }
  }
  { decls, }
}

///|
fn Parser::parse_attributes(self : Parser) -> Array[Attribute] raise Failed {
  let attrs = []
  while self.at_punct(At) {
    ignore(self.advance())
    let (name, span) = self.expect_ident()
    let args = []
    if self.eat_punct(ParenLeft) {
      while !self.at_punct(ParenRight) {
        // An argument is a word when the name is followed by `,` or `)`;
        // otherwise it is an expression, as in `@workgroup_size(8, 8)`.
        match self.peek_kind() {
          Ident(word) => {
            let next = self.tokens[self.pos.to_int() + 1]
            let is_word = match next.kind {
              Punct(Comma) | Punct(ParenRight) => true
              _ => false
            }
            if is_word {
              ignore(self.advance())
              args.push(Word(word, span))
            } else {
              args.push(Value(self.parse_expr()))
            }
          }
          _ => args.push(Value(self.parse_expr()))
        }
        if !self.eat_punct(Comma) {
          break
        }
      }
      ignore(self.expect_punct(ParenRight))
    }
    attrs.push({ name, args, span, })
  }
  attrs
}

///|
fn Parser::parse_const_decl(
  self : Parser,
  span : @moonnaga.Span,
) -> ConstDecl raise Failed {
  let (name, _) = self.expect_ident()
  let mut ty = None
  if self.eat_punct(Colon) {
    ty = Some(self.parse_type())
  }
  ignore(self.expect_punct(Equal))
  let init = self.parse_expr()
  ignore(self.expect_punct(Semicolon))
  { name, ty, init, span, }
}

///|
fn Parser::parse_override_decl(
  self : Parser,
  attrs : Array[Attribute],
  span : @moonnaga.Span,
) -> OverrideDecl raise Failed {
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
  { attrs, name, ty, init, span, }
}

///|
fn Parser::parse_global_var(
  self : Parser,
  attrs : Array[Attribute],
  span : @moonnaga.Span,
) -> VarDecl raise Failed {
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
  { attrs, name, space, ty, init, span, }
}

///|
/// The `<storage, read_write>` that follows `var`.
fn Parser::parse_address_space(self : Parser) -> String? raise Failed {
  if !self.at_punct(Less) {
    return None
  }
  ignore(self.advance())
  let (space, _) = self.expect_ident()
  let mut access = None
  if self.eat_punct(Comma) {
    let (word, _) = self.expect_ident()
    access = Some(word)
  }
  self.expect_greater()
  match access {
    None => Some(space)
    Some(name) => Some("\{space},\{name}")
  }
}

///|
fn Parser::parse_struct_decl(
  self : Parser,
  span : @moonnaga.Span,
) -> StructDecl raise Failed {
  let (name, _) = self.expect_ident()
  ignore(self.expect_punct(BraceLeft))
  let fields : Array[StructFieldDecl] = []
  while !self.at_punct(BraceRight) {
    let attrs = self.parse_attributes()
    let (field_name, field_span) = self.expect_ident()
    ignore(self.expect_punct(Colon))
    let ty = Some(self.parse_type())
    fields.push({ attrs, name: field_name, ty, span: field_span, })
    if !self.eat_punct(Comma) {
      break
    }
  }
  ignore(self.expect_punct(BraceRight))
  ignore(self.eat_punct(Semicolon))
  { name, fields, span, }
}

///|
fn Parser::parse_fn_decl(
  self : Parser,
  attrs : Array[Attribute],
  span : @moonnaga.Span,
) -> FnDecl raise Failed {
  let (name, _) = self.expect_ident()
  ignore(self.expect_punct(ParenLeft))
  let params : Array[ParamDecl] = []
  while !self.at_punct(ParenRight) {
    let param_attrs = self.parse_attributes()
    let (param_name, param_span) = self.expect_ident()
    ignore(self.expect_punct(Colon))
    let ty = self.parse_type()
    params.push({ attrs: param_attrs, name: param_name, ty, span: param_span, })
    if !self.eat_punct(Comma) {
      break
    }
  }
  ignore(self.expect_punct(ParenRight))
  let mut result = { attrs: [], ty: None, span, }
  if self.eat_punct(Arrow) {
    let result_attrs = self.parse_attributes()
    let ty = Some(self.parse_type())
    result = { attrs: result_attrs, ty, span, }
  }
  let body = self.parse_block()
  { attrs, name, params, result, body, span, }
}
