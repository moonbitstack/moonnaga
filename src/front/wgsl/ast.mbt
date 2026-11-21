// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One argument of an attribute. Some attributes take expressions, some take
/// bare words such as `flat` or `read_write`.
#derive(Debug)
pub(all) enum AttributeArg {
  Word(String, @moonnaga.Span)
  Value(Expr)
}

///|
#derive(Debug)
pub(all) struct Attribute {
  name : String
  args : Array[AttributeArg]
  span : @moonnaga.Span
}

///|
/// A type as the source writes it: a name with template arguments, which may be
/// types or expressions depending on the name, or the pointer form.
#derive(Debug)
pub(all) enum TypeExpr {
  Named(String, Array[TemplateArg], @moonnaga.Span)
  Pointer(PointerExpr)
}

///|
#derive(Debug)
pub(all) struct PointerExpr {
  space : String
  base : TypeExpr
  access : String?
  span : @moonnaga.Span
}

///|
#derive(Debug)
pub(all) enum TemplateArg {
  Type(TypeExpr)
  Expr(Expr)
}

///|
#derive(Eq, Debug)
pub(all) enum UnaryOp {
  Negate
  LogicalNot
  BitwiseNot
  AddressOf
  Deref
}

///|
#derive(Eq, Debug)
pub(all) enum BinaryOp {
  Add
  Subtract
  Multiply
  Divide
  Modulo
  Equal
  NotEqual
  Less
  LessEqual
  Greater
  GreaterEqual
  And
  Or
  Xor
  LogicalAnd
  LogicalOr
  ShiftLeft
  ShiftRight
}

///|
/// An expression tree, before any type is known about it.
#derive(Debug)
pub(all) enum Expr {
  /// A number literal, keeping its spelling so the abstract types can tell an
  /// integer literal from a floating one.
  Number(NumberLit, @moonnaga.Span)
  Bool(Bool, @moonnaga.Span)
  Ident(String, @moonnaga.Span)
  UnaryApply(UnaryOp, Expr, @moonnaga.Span)
  BinaryApply(BinaryOp, Expr, Expr, @moonnaga.Span)
  /// A call: a type constructor such as `vec4<f32>(...)`, a builtin function, or
  /// a call to a function the module declares. Which one it is is decided when
  /// the types are known.
  Invoke(String, Array[TemplateArg], Array[Expr], @moonnaga.Span)
  /// A call whose callee is itself an expression, which only `bitcast` needs.
  Bitcast(Array[TemplateArg], Expr, @moonnaga.Span)
  Index(Expr, Expr, @moonnaga.Span)
  Member(Expr, String, @moonnaga.Span)
}

///|
#derive(Eq, Debug)
pub(all) enum AssignOp {
  Assign
  Add
  Subtract
  Multiply
  Divide
  Modulo
  And
  Or
  Xor
  ShiftLeft
  ShiftRight
}

///|
#derive(Debug)
pub(all) struct SwitchArm {
  /// `None` for `default`.
  value : Expr?
  body : Array[Stmt]
}

///|
#derive(Debug)
pub(all) struct ForParts {
  init : Stmt?
  condition : Expr?
  update : Stmt?
  body : Array[Stmt]
}

///|
#derive(Debug)
pub(all) enum Stmt {
  SExpr(Expr)
  SAssign(Expr, AssignOp, Expr, @moonnaga.Span)
  SIncrement(Expr, Int32, @moonnaga.Span)
  SLet(String, TypeExpr?, Expr?, Array[Attribute], @moonnaga.Span)
  SVar(String, TypeExpr?, Expr?, Array[Attribute], String?, @moonnaga.Span)
  SConst(String, TypeExpr?, Expr, @moonnaga.Span)
  SIf(Expr, Array[Stmt], Array[Stmt])
  SLoop(Array[Stmt], Array[Stmt], Expr?)
  SFor(ForParts)
  SWhile(Expr, Array[Stmt])
  SSwitch(Expr, Array[SwitchArm])
  SBreak(@moonnaga.Span)
  SContinue(@moonnaga.Span)
  SReturn(Expr?)
  SDiscard(@moonnaga.Span)
  SBlock(Array[Stmt])
  SConstAssert(Expr, @moonnaga.Span)
  /// A `;` with nothing in front of it.
  SEmpty
}

///|
#derive(Debug)
pub(all) struct StructFieldDecl {
  attrs : Array[Attribute]
  name : String
  ty : TypeExpr?
  span : @moonnaga.Span
}

///|
#derive(Debug)
pub(all) struct StructDecl {
  name : String
  fields : Array[StructFieldDecl]
  span : @moonnaga.Span
}

///|
#derive(Debug)
pub(all) struct ParamDecl {
  attrs : Array[Attribute]
  name : String
  ty : TypeExpr
  span : @moonnaga.Span
}

///|
#derive(Debug)
pub(all) struct ReturnDecl {
  attrs : Array[Attribute]
  ty : TypeExpr?
  span : @moonnaga.Span
}

///|
#derive(Debug)
pub(all) struct FnDecl {
  attrs : Array[Attribute]
  name : String
  params : Array[ParamDecl]
  result : ReturnDecl
  body : Array[Stmt]
  span : @moonnaga.Span
}

///|
#derive(Debug)
pub(all) struct VarDecl {
  attrs : Array[Attribute]
  name : String
  space : String?
  ty : TypeExpr?
  init : Expr?
  span : @moonnaga.Span
}

///|
#derive(Debug)
pub(all) struct ConstDecl {
  name : String
  ty : TypeExpr?
  init : Expr
  span : @moonnaga.Span
}

///|
#derive(Debug)
pub(all) struct OverrideDecl {
  attrs : Array[Attribute]
  name : String
  ty : TypeExpr?
  init : Expr?
  span : @moonnaga.Span
}

///|
/// A declaration at module scope, in the order the source writes it.
#derive(Debug)
pub(all) enum Decl {
  Enable(String)
  Requires(String)
  /// A diagnostic filter. The filters steer the messages a compiler emits, and
  /// this library reports every rule it checks, so they are recorded and
  /// otherwise have no effect.
  Diagnostic(String, String?)
  Const(ConstDecl)
  Override(OverrideDecl)
  Var(VarDecl)
  Struct(StructDecl)
  Alias(String, TypeExpr, @moonnaga.Span)
  Fn(FnDecl)
  ConstAssert(Expr, @moonnaga.Span)
}

///|
/// A parsed source file: declarations in source order, plus the enables and the
/// requires it asked for.
#derive(Debug)
pub(all) struct TranslationUnit {
  decls : Array[Decl]
}
