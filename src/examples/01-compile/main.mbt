// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A compute shader that adds two buffers, which is the smallest shader that
/// reaches every stage of the pipeline: resources, an entry point, a loop and
/// arithmetic.
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
#coverage.skip
fn main {
  // The whole pipeline in four calls: read, check, write, report.
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
      println("invalid: \{error.message} (\{error.subject})")
      return
    }
  }
  println(@writer.write_module(shader))
  println("entry points: \{info.entry_points.length()}")
}
