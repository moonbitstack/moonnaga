// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Storage classes, as the specification numbers them.
pub let class_uniform_constant : Word = 0

///|
/// An entry point input.
pub let class_input : Word = 1

///|
/// An entry point output.
pub let class_output : Word = 3

///|
pub let class_uniform : Word = 2

///|
pub let class_workgroup : Word = 4

///|
pub let class_private : Word = 6

///|
pub let class_function : Word = 7

///|
pub let class_push_constant : Word = 9

///|
pub let class_storage_buffer : Word = 12

///|
pub let decoration_block : Word = 2

///|
pub let decoration_array_stride : Word = 6

///|
pub let decoration_builtin : Word = 11

///|
pub let decoration_no_perspective : Word = 13

///|
pub let decoration_flat : Word = 14

///|
pub let decoration_centroid : Word = 16

///|
pub let decoration_sample : Word = 17

///|
pub let decoration_location : Word = 30

///|
pub let decoration_binding : Word = 33

///|
pub let decoration_descriptor_set : Word = 34

///|
pub let builtin_position : Word = 0

///|
pub let builtin_point_size : Word = 1

///|
pub let builtin_clip_distance : Word = 3

///|
pub let builtin_cull_distance : Word = 4

///|
pub let builtin_primitive_id : Word = 7

///|
pub let builtin_point_coord : Word = 16

///|
pub let builtin_front_facing : Word = 17

///|
pub let builtin_sample_id : Word = 18

///|
pub let builtin_sample_mask : Word = 20

///|
pub let builtin_frag_depth : Word = 22

///|
pub let builtin_num_workgroups : Word = 24

///|
pub let builtin_workgroup_size : Word = 25

///|
pub let builtin_workgroup_id : Word = 26

///|
pub let builtin_local_invocation_id : Word = 27

///|
pub let builtin_global_invocation_id : Word = 28

///|
pub let builtin_local_invocation_index : Word = 29

///|
pub let builtin_vertex_index : Word = 42

///|
pub let builtin_instance_index : Word = 43

///|
pub let builtin_draw_index : Word = 4426

///|
pub let builtin_view_index : Word = 4441

///|
/// What a module is being translated for, which decides the capability list and
/// the memory model.
#derive(Eq, Debug)
pub(all) struct Options {
  /// The SPIR-V version as major * 10000 + minor * 100 + patch, so 1.0 is
  /// 10000 and 1.3 is 10300.
  version : Word
}

///|
pub let options_default : Options = { version: 10300, }

///|
/// The ids of the types and constants a module has already written, so a type
/// used twice is one entry.
pub(all) struct TypeCache {
  ids : Map[Int32, Word]
  void_id : Word
  bool_id : Word
  mat_null : Map[Int32, Word]
  sampled_image : Map[Int32, Word]
}

///|
pub fn TypeCache::new(void_id : Word, bool_id : Word) -> TypeCache {
  { ids: Map([]), void_id, bool_id, mat_null: Map([]), sampled_image: Map([]), }
}
