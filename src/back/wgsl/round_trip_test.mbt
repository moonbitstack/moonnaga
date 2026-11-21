// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A shader that uses the pieces a round trip has to keep: a struct, a
/// constant, a resource binding, two entry points and a discard.
let quad : String =
  #|const c_scale: f32 = 1.2;
  #|
  #|struct VertexOutput {
  #|  @location(0) uv: vec2<f32>,
  #|  @builtin(position) position: vec4<f32>,
  #|}
  #|
  #|@vertex
  #|fn vert_main(@location(0) pos: vec2<f32>, @location(1) uv: vec2<f32>) -> VertexOutput {
  #|  return VertexOutput(uv, vec4<f32>(c_scale * pos, 0.0, 1.0));
  #|}
  #|
  #|@group(0) @binding(0) var u_texture: texture_2d<f32>;
  #|@group(0) @binding(1) var u_sampler: sampler;
  #|
  #|@fragment
  #|fn frag_main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
  #|  let colour = textureSample(u_texture, u_sampler, uv);
  #|  if (colour.a == 0.0) {
  #|    discard;
  #|  }
  #|  return colour.a * colour;
  #|}

///|
test "a shader comes back as WGSL" {
  let shader = match @front.parse(quad) {
    Ok(shader) => shader
    Err(error) => {
      println("parse failed at \{error.line}:\{error.column}: \{error.message}")
      abort("the shader does not parse")
    }
  }
  let text = @wgsl.write_module(shader)
  println(text)
  assert_true(text.contains("struct VertexOutput"))
  assert_true(text.contains("fn vert_main"))
  assert_true(text.contains("fn frag_main"))
}

///|
test "a struct field keeps its binding" {
  let shader = match @front.parse(quad) {
    Ok(shader) => shader
    Err(_) => abort("the shader does not parse")
  }
  let text = @wgsl.write_module(shader)
  assert_true(text.contains("@location(0) uv: vec2<f32>"))
  assert_true(text.contains("@builtin(position) position: vec4<f32>"))
}
