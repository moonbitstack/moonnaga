// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn parsed(source : String) -> @moonnaga.Module {
  match @wgsl.parse(source) {
    Ok(shader) => shader
    Err(error) => abort("the shader does not parse: " + error.message)
  }
}

///|
test "a scalar times a vector has the vector's type" {
  let shader = parsed("const c = 2.0 * vec2<f32>(1.0);")
  let constant = shader.constants.get(@moonnaga.Handle::new(0))
  assert_eq(shader.types.get(constant.ty).inner.name(), "vec2<f32>")
}

///|
test "an abstract literal takes the width its context asks for" {
  let shader = parsed(
    (
      #|@compute @workgroup_size(1)
      #|fn f() {
      #|  var a: f32 = 1;
      #|  var b: u32 = 2;
      #|}
    ),
  )
  let function = shader.functions.get(@moonnaga.Handle::new(0))
  assert_eq(function.local_variables.len(), 2)
  assert_eq(
    shader.types.get(function.local_variables.get(@moonnaga.Handle::new(0)).ty).inner.name(),
    "f32",
  )
  assert_eq(
    shader.types.get(function.local_variables.get(@moonnaga.Handle::new(1)).ty).inner.name(),
    "u32",
  )
}

///|
test "a matrix times a vector narrows to the rows" {
  let shader = parsed(
    "const c = mat2x3<f32>(vec3<f32>(1.0), vec3<f32>(2.0)) * vec2<f32>(1.0);",
  )
  let constant = shader.constants.get(@moonnaga.Handle::new(0))
  assert_eq(shader.types.get(constant.ty).inner.name(), "vec3<f32>")
}
