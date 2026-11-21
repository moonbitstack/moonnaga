// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a numeric literal keeps its suffix" {
  let tokens = @wgsl.tokenize("1 2u 3i 4f 5h 0x1f 1.5e3")
  let kinds = []
  for token in tokens {
    match token.kind {
      @wgsl.Number(number) =>
        kinds.push(
          number.text + "/" + (if number.is_float { "float" } else { "int" }),
        )
      _ => ()
    }
  }
  assert_eq(kinds, [
    "1/int", "2/int", "3/int", "4/int", "5/int", "0x1f/int", "1.5e3/float",
  ])
}

///|
test "a block comment nests" {
  let tokens = @wgsl.tokenize("/* a /* b */ c */ let")
  assert_eq(tokens.length(), 2)
  match tokens[0].kind {
    @wgsl.Ident(name) => assert_eq(name, "let")
    _ => abort("expected an identifier")
  }
}

///|
test "an unterminated block comment is refused" {
  let result = try {
    ignore(@wgsl.tokenize("/* still open"))
    Ok(())
  } catch {
    @wgsl.Failed(error) => Err(error)
  }
  match result {
    Ok(_) => abort("the lexer accepted an unterminated comment")
    Err(error) => assert_eq(error.message, "an unterminated block comment")
  }
}
