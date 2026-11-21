// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a diagnostic carries the line and the column" {
  let source : String =
    #|fn f() {
    #|  let x = ;
    #|}
  match @wgsl.parse(source) {
    Ok(_) => abort("the source should not parse")
    Err(error) => {
      assert_eq(error.line, 2)
      assert_true(error.column > 0)
      assert_true(error.message.contains("expression"))
    }
  }
}

///|
test "a condition takes parentheses or leaves them out" {
  let with_parens : String =
    #|@compute @workgroup_size(1)
    #|fn f() {
    #|  if (1 == 1) { return; }
    #|}
  let without_parens : String =
    #|@compute @workgroup_size(1)
    #|fn f() {
    #|  if 1 == 1 { return; }
    #|}
  assert_true(@wgsl.parse(with_parens) is Ok(_))
  assert_true(@wgsl.parse(without_parens) is Ok(_))
}

///|
test "two template lists close with one shift token" {
  let source : String =
    #|@group(0) @binding(0) var<storage, read> data: array<array<f32, 2>, 3>;
  assert_true(@wgsl.parse(source) is Ok(_))
}

///|
test "a pointer parameter is a reference in the body" {
  let source : String =
    #|fn twice(p: ptr<function, f32>) {
    #|  *p = *p * 2.0;
    #|}
  assert_true(@wgsl.parse(source) is Ok(_))
}
