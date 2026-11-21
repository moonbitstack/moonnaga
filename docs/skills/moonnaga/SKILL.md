---
name: moonnaga
description: "Compile WGSL shaders from MoonBit: parse, validate, and write back WGSL or SPIR-V. Use when a program has to check a shader before handing it to a GPU, when a pipeline needs the SPIR-V bytes for Vulkan, or when a tool has to read a shader's entry points and bindings."
---

# moonnaga

A WGSL compiler. Source text in, a validated module out, and SPIR-V or WGSL from
that module.

## Install

```sh
moon add moonbitstack/moonnaga
```

The whole pipeline is behind one import:

```mbt
import {
  "moonbitstack/moonnaga/compile" @compile,
}
```

## Compile a shader

`@compile.parse` returns the module or a diagnostic with a line and a column;
`@compile.validate` checks it against the language and the capabilities the
device declares; the writers take it from there.

```mbt check
///|
test {
  let source =
    #|@compute @workgroup_size(64)
    #|fn add(@builtin(global_invocation_id) id: vec3<u32>) {
    #|  let i = id.x;
    #|}
  match @compile.parse(source) {
    Ok(shader) => {
      let info = match @compile.validate(shader) {
        Ok(info) => info
        Err(error) => abort(error.message)
      }
      assert_eq(info.entry_points.length(), 1)
      assert_true(@compile.write_wgsl(shader).contains("@compute"))
    }
    Err(error) => abort(error.message)
  }
}
```

## Get the SPIR-V

`write_spirv` produces the binary a Vulkan driver loads. It refuses what it
cannot translate, by name, instead of writing something approximate:

```mbt check
///|
test {
  let source =
    #|@compute @workgroup_size(1)
    #|fn main() { }
  let shader = match @compile.parse(source) {
    Ok(shader) => shader
    Err(_) => abort("the shader does not parse")
  }
  let info = match @compile.validate(shader) {
    Ok(info) => info
    Err(_) => abort("the shader does not validate")
  }
  let bytes = @compile.write_spirv(shader, info) catch {
    _ => abort("the shader is not translatable")
  }
  // Every SPIR-V module starts with the same magic number.
  assert_eq(bytes[0], 0x03)
  assert_eq(bytes[3], 0x07)
}
```

## Turn a feature on

A module that needs `f16`, 64-bit integers or push constants is refused unless
the capability is asked for, which is what keeps it from being accepted here and
refused by the device:

```mbt check
///|
test {
  let source =
    #|var<private> big: i64 = 1li;
    #|@compute @workgroup_size(1) fn main() { big = 2li; }
  let shader = match @compile.parse(source) {
    Ok(shader) => shader
    Err(_) => abort("the shader does not parse")
  }
  assert_eq(@compile.validate(shader) is Ok(_), false)
  assert_eq(
    @compile.validate(shader, capabilities=@valid.capabilities_all) is Ok(_),
    true,
  )
}
```

## Things to know

- The library does no I/O: the same code runs on all four targets. Reading a
  file and writing the result is the caller's job.
- A diagnostic's `line` and `column` count from one, and the column counts
  characters rather than bytes.
- `write_spirv` can fail with `@spv.Unsupported`; the payload names the construct.
- An entry point's arguments are interface variables in SPIR-V, because a Vulkan
  entry point takes no parameters. Do not expect them as `OpFunctionParameter`.
