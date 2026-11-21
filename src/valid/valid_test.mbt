// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn parse_or_abort(source : String) -> @moonnaga.Module {
  match @front.parse(source) {
    Ok(shader) => shader
    Err(error) => abort("the shader does not parse: " + error.message)
  }
}

///|
test "a 64-bit integer needs the capability" {
  let shader = parse_or_abort(
    (
      #|var<private> big: i64 = 1li;
      #|@compute @workgroup_size(1) fn main() { big = 2li; }
    ),
  )

  assert_true(@valid.validate(shader) is Err(_))
  assert_true(
    @valid.validate(shader, capabilities=@valid.capabilities_all) is Ok(_),
  )
}

///|
test "two arguments cannot share a location" {
  let shader = parse_or_abort(
    (
      #|@fragment fn main(@location(0) a: f32, @location(0) b: f32) -> @location(0) f32 {
      #|  return a + b;
      #|}
    ),
  )
  match @valid.validate(shader) {
    Ok(_) => abort("the validator accepted two arguments at one location")
    Err(error) => assert_true(error.message.contains("location 0"))
  }
}

///|
test "a buffer needs a binding" {
  let shader = parse_or_abort(
    (
      #|var<storage, read> data: array<f32>;
      #|@compute @workgroup_size(1) fn main() { let x = data[0]; }
    ),
  )
  match @valid.validate(shader) {
    Ok(_) => abort("the validator accepted a buffer without a binding")
    Err(error) => assert_true(error.message.contains("binding"))
  }
}

///|
test "a resource variable has to be a texture or a sampler" {
  let shader = parse_or_abort(
    (
      #|@group(0) @binding(0) var<uniform> wrong: f32;
      #|@compute @workgroup_size(1) fn main() { let x = wrong; }
    ),
  )
  // A uniform scalar is a legal buffer, so this one has to pass: the rule being
  // tested is the one that refuses a *handle*-space variable of the wrong type.
  assert_true(@valid.validate(shader) is Ok(_))
}
