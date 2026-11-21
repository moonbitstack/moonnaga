// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the four stages run in a row" {
  let source : String =
    #|@compute @workgroup_size(64)
    #|fn add(@builtin(global_invocation_id) id: vec3<u32>) {
    #|  let index = id.x;
    #|}
  let shader = match @compile.parse(source) {
    Ok(shader) => shader
    Err(error) => abort("the shader does not parse: " + error.message)
  }
  let info = match @compile.validate(shader) {
    Ok(info) => info
    Err(error) => abort("the shader does not validate: " + error.message)
  }
  assert_eq(info.entry_points.length(), 1)
  assert_true(@compile.write_wgsl(shader).contains("fn add("))
  let bytes = @compile.write_spirv(shader, info) catch {
    @spv.Unsupported(reason) => abort("unsupported: " + reason.feature)
  }
  assert_true(bytes.length() > 0)
}
