// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Cases 72 to 73 of the corpus.
pub fn chunk_6() -> Array[(String, String, String)] {
  [
    (
      "workgroup-uniform-load", "const SIZE: u32 = 128u;\n\nvar<workgroup> arr_i32: array<i32, SIZE>;\n\n@compute @workgroup_size(4)\nfn test_workgroupUniformLoad(@builtin(workgroup_id) workgroup_id: vec3<u32>) {\n    let x = &arr_i32[workgroup_id.x];\n    let val = workgroupUniformLoad(x);\n    if val > 10 {\n        workgroupBarrier();\n    }\n}\n",
      "const SIZE: u32 = 128u;\n\nvar<workgroup> arr_i32_: array<i32, 128>;\n\n@compute @workgroup_size(4, 1, 1) \nfn test_workgroupUniformLoad(@builtin(workgroup_id) workgroup_id: vec3<u32>) {\n    let x = (&arr_i32_[workgroup_id.x]);\n    let _e4 = workgroupUniformLoad(x);\n    if (_e4 > 10i) {\n        workgroupBarrier();\n        return;\n    } else {\n        return;\n    }\n}\n",
    ),
    (
      "workgroup-var-init", "struct WStruct {\n    arr: array<u32, 512>,\n    atom: atomic<i32>,\n    atom_arr: array<array<atomic<i32>, 8>, 8>,\n}\n\nvar<workgroup> w_mem: WStruct;\n\n@group(0) @binding(0)\nvar<storage, read_write> output: array<u32, 512>;\n\n@compute @workgroup_size(1)\nfn main() {\n    output = w_mem.arr;\n}",
      "struct WStruct {\n    arr: array<u32, 512>,\n    atom: atomic<i32>,\n    atom_arr: array<array<atomic<i32>, 8>, 8>,\n}\n\nvar<workgroup> w_mem: WStruct;\n@group(0) @binding(0) \nvar<storage, read_write> output: array<u32, 512>;\n\n@compute @workgroup_size(1, 1, 1) \nfn main() {\n    let _e3 = w_mem.arr;\n    output = _e3;\n    return;\n}\n",
    ),
  ]
}
