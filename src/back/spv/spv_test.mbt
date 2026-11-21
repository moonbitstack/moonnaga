// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn compile(source : String) -> Array[Byte] raise @spv.SpvError {
  let shader = match @front.parse(source) {
    Ok(shader) => shader
    Err(error) => abort("the shader does not parse: " + error.message)
  }
  let info = match @validate.validate(shader) {
    Ok(info) => info
    Err(error) => abort("the shader does not validate: " + error.message)
  }
  @spv.write_module(shader, info)
}

///|
/// The first word of every SPIR-V module.
let magic : Array[Byte] = [0x03, 0x02, 0x23, 0x07]

///|
test "the header is the one the format fixes" {
  let bytes = compile(
    (
      #|@compute @workgroup_size(1) fn main() { }
    ),
  )
  assert_eq(bytes.length() % 4, 0)
  for index in 0..<4 {
    assert_eq(bytes[index], magic[index])
  }
  // The version word: 1.3, which is what the writer emits for storage buffers.
  assert_eq(bytes[4], 0x00)
  assert_eq(bytes[5], 0x03)
  assert_eq(bytes[6], 0x01)
  assert_eq(bytes[7], 0x00)
}

///|
test "a name ends with a word of its own when it fills one" {
  // Twelve characters fill three words exactly, and the terminator needs a
  // fourth.
  let words = @spv.string_words("GLSL.std.450")
  assert_eq(words.length(), 4)
  assert_eq(words[3], 0)
}

///|
test "the bound covers every id" {
  let bytes = compile(
    (
      #|@compute @workgroup_size(4) fn main() { }
    ),
  )
  let bound = bytes[12].to_int() |
    (bytes[13].to_int() << 8) |
    (bytes[14].to_int() << 16) |
    (bytes[15].to_int() << 24)
  assert_true(bound > 1)
}
