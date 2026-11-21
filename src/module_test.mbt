// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a vec3 aligns like a vec4" {
  let shader_module = @moonnaga.Module::new()
  let scalar = shader_module.types.add(
    @moonnaga.Type::new(None, @moonnaga.Scalar(@moonnaga.scalar_f32)),
  )
  let vector = shader_module.types.add(
    @moonnaga.Type::new(
      None,
      @moonnaga.Vector({ size: @moonnaga.Tri, scalar: @moonnaga.scalar_f32, }),
    ),
  )
  let layout = shader_module.layout(vector, 0)
  assert_eq(layout.size, 12)
  assert_eq(layout.alignment, 16)
  assert_eq(shader_module.layout(scalar, 0).alignment, 4)
}

///|
test "a struct rounds its span up to its alignment" {
  let shader_module = @moonnaga.Module::new()
  let scalar = shader_module.types.add(
    @moonnaga.Type::new(None, @moonnaga.Scalar(@moonnaga.scalar_f32)),
  )
  let vector = shader_module.types.add(
    @moonnaga.Type::new(
      None,
      @moonnaga.Vector({ size: @moonnaga.Tri, scalar: @moonnaga.scalar_f32, }),
    ),
  )
  let structure = shader_module.types.add(
    @moonnaga.Type::new(
      Some("S"),
      @moonnaga.Struct({
        members: [
          {
            name: "a",
            ty: vector,
            binding: None,
            offset: 0,
            interpolate: None,
          },
          {
            name: "b",
            ty: scalar,
            binding: None,
            offset: 16,
            interpolate: None,
          },
        ],
        span: 20,
      }),
    ),
  )
  let layout = shader_module.layout(structure, 0)
  assert_eq(layout.size, 20)
  assert_eq(layout.alignment, 16)
  assert_eq(layout.alignment, 16)
}
