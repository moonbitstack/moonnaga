# moonnaga

The WGSL front end for MoonBit: source in, validated intermediate representation
out, and machine code for the targets the native graphics APIs take.

Named after [naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga), the shader
translator that sits inside wgpu. This repository is the same idea written in
MoonBit, against the WGSL specification rather than against naga's internals.

## What it is

A compiler. It reads WGSL text, checks it against the language specification,
builds an IR, and writes that IR out as SPIR-V, MSL, HLSL or WGSL again.

It is the shader half of the WebGPU stack. `moonwgpu` owns the API objects,
validation of descriptor data, command recording and the backend contract; this
library owns everything that happens between a string of WGSL and the bytes a
driver consumes.

## Responsibility

| It does | It does not |
|:--|:--|
| Parse WGSL into an AST and lower it to an IR | Create devices, adapters or queues |
| Validate a module against the WGSL specification, with the rules the WebGPU feature set switches on | Talk to Vulkan, Metal, D3D12 or GL through FFI; that is the `hal` side of `moonwgpu` |
| Report diagnostics with source spans, severities and messages | Own the WebGPU API types; the descriptors stay in `moonwgpu/types` |
| Reflect over a module: entry points, their stage, their resources, the binding space they address, the immediate ranges they declare | Decide bind group layouts on its own; it reports what the module needs, the caller decides |
| Emit SPIR-V, MSL, HLSL, and WGSL back out | Link, load or dispatch shaders |
| Keep the IR stable enough to be a target for future front ends | Promise compatibility with naga's own IR definition |

## Scope

The language surface is the one the WebGPU specification binds: WGSL as
published by the W3C, plus the extensions that WebGPU features enable. Two
consequences worth stating up front:

- **Feature-gated syntax is gated here too.** A module that uses a construct
  belonging to a disabled feature is refused with a diagnostic that names the
  feature, not silently accepted.
- **The target set follows the backends.** SPIR-V for Vulkan, MSL for Metal,
  HLSL for D3D12, WGSL for round trips and for the browser path where the driver
  compiles WGSL itself.

Deliberately out of scope for the first release, though naga has them:

| Left out | Why |
|:--|:--|
| GLSL and HLSL front ends | Nothing in the stack produces them; the WebGPU API only takes WGSL |
| SPIR-V as an input language | A caller that has SPIR-V already has a compiler; accepting it would make the IR a second-class citizen |
| GLSL as an output language | The GLES path is served by SPIR-V and a driver that consumes it, or by WGSL where the platform allows |
| Shader linking, pipeline caching on disk | Caller concerns; a cache key can be built from a module's hash, which the IR exposes |

## Layers

The shape is the one naga settled on, and it is the shape that keeps the front
end and the four writers from knowing about each other.

```
wgsl (front end)  ->  ir  ->  validators  ->  spirv | msl | hlsl | wgsl (back ends)
```

- `ir`: the language after parsing, before any target's opinions. Types,
  expressions, statements, entry points, resource bindings, constants,
  immediate ranges.
- `validators`: the rules of the language and of the WebGPU feature set. They
  run once, over the IR, and every back end can then assume a well-formed
  module.
- Back ends: one package per target. A back end reads the IR and writes bytes or
  text. Nothing else.

Package boundaries follow the organization's rule: one format or one algorithm
per leaf package, so a build that only needs SPIR-V does not carry the MSL
writer.

## Where it sits

| Neighbour | Relationship |
|:--|:--|
| `moonwgpu` | consumer. `createShaderModule` hands a module here, `getCompilationInfo` takes the diagnostics back, and pipeline layout inference takes the reflection |
| `moonapp` | unrelated; surfaces and presentation do not involve shaders |
| `moongfx`, `moonggml` | indirect consumers, through `moonwgpu` |
| `moonbitlang/core`, `moonbitstack/*` | the only allowed dependencies, and never a dependency back on `moonwgpu` |

## Status

Pre-architecture. The package layout, the IR and the public entry points are
being designed; this file records the boundary they must stay inside. There is no
code yet, and no release.

## References

- WGSL specification: <https://www.w3.org/TR/WGSL/>
- WGSL draft: <https://gpuweb.github.io/gpuweb/wgsl/>
- WebGPU specification, for the validation rules a shader module must satisfy:
  <https://www.w3.org/TR/webgpu/>
- naga, the Rust implementation this library is named after:
  <https://github.com/gfx-rs/wgpu/tree/trunk/naga>

## Licence

Apache-2.0. See `LICENSE`.
