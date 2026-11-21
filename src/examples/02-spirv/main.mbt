// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The same shader the first example compiles, so the two runs can be compared.
let shader : String =
  #|@group(0) @binding(0) var<storage, read> left: array<f32>;
  #|@group(0) @binding(1) var<storage, read> right: array<f32>;
  #|@group(0) @binding(2) var<storage, read_write> sum: array<f32>;
  #|
  #|@compute @workgroup_size(64)
  #|fn add(@builtin(global_invocation_id) id: vec3<u32>) {
  #|  let index = id.x;
  #|  sum[index] = left[index] + right[index];
  #|}

///|
/// A byte as two hexadecimal digits, which is how the binary is printed: a
/// terminal and a test log both carry text, and `xxd -r -p` turns it back into
/// the file a driver expects.
fn hex(byte : Byte) -> String {
  let digits = "0123456789abcdef"
  let value = byte.to_int()
  let high = digits.to_array()[value / 16]
  let low = digits.to_array()[value % 16]
  String::from_array([high, low])
}

///|
#coverage.skip
fn main {
  let shader = match @wgsl.parse(shader) {
    Ok(shader) => shader
    Err(error) => {
      println("error at \{error.line}:\{error.column}: \{error.message}")
      return
    }
  }
  let info = match @valid.validate(shader) {
    Ok(info) => info
    Err(error) => {
      println("invalid: \{error.message}")
      return
    }
  }
  let bytes = @spv.write_module(shader, info) catch {
    @spv.Unsupported(reason) => {
      println("unsupported: \{reason.feature}")
      return
    }
  }
  let builder = StringBuilder()
  for byte in bytes {
    builder.write_string(hex(byte))
  }
  println(builder.to_string())
}
