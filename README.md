# moonnaga

The WGSL front end for MoonBit: shader source in, a validated intermediate
representation out, and SPIR-V or WGSL for the targets a driver takes.

A compiler, in four passes: parse, lower, validate, write. It implements the
language the WebGPU specification binds — [WGSL](https://www.w3.org/TR/WGSL/) —
and the validation rules a shader module has to satisfy before a device may run
it.

## What it does

| It does | It does not |
|:--|:--|
| Read WGSL into an abstract syntax tree, with diagnostics that carry a line and a column | Create devices, adapters or queues |
| Lower it to an intermediate representation: types, constants, globals, functions, expressions and statements, in arenas | Talk to Vulkan, Metal, D3D12 or GL; that is the `hal` side of `moonwgpu` |
| Validate a module against the language and the feature set the caller declares | Own the WebGPU API types; the descriptors stay in `moonwgpu/types` |
| Write the module back as WGSL | Link, load or dispatch shaders |
| Write the module as a SPIR-V binary | Promise compatibility with any other compiler's internal representation |

## Use

```mbt check
///|
test {
  let source =
    #|@compute @workgroup_size(64)
    #|fn add(@builtin(global_invocation_id) id: vec3<u32>) {
    #|  let i = id.x;
    #|}
  let shader = match @compile.parse(source) {
    Ok(shader) => shader
    Err(error) => {
      // `error.line` and `error.column` say where, `error.message` says what.
      abort(error.message)
    }
  }
  let text = @compile.write_wgsl(shader)
  assert_true(text.contains("fn add("))
}
```

SPIR-V, once the module validates:

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
  assert_eq(bytes[0], 0x03)
}
```

## Packages

One package per stage, so a build that only needs the front end does not carry a
writer.

| Package | What is in it |
|:--|:--|
| `moonnaga` | the intermediate representation, and the pass that builds it from source |
| `moonnaga/front/wgsl` | lexer, parser, lowering: WGSL text in, a module out |
| `moonnaga/valid` | the validation rules and the capability record |
| `moonnaga/back/wgsl` | the module back out as WGSL text |
| `moonnaga/back/spv` | the module out as a SPIR-V binary |
| `moonnaga/compile` | the four stages behind one import, for a caller that wants the pipeline rather than a stage |
| `moonnaga/conformance` | the snapshot replay against another compiler's recorded output |

## The representation

An arena of types, constants, global variables, functions, expressions and
statements. Expressions are flat: a node names its operands by handle, in
evaluation order, which is what lets a writer decide where a temporary is needed
without walking the same subtree twice.

- **Types**: scalars, vectors, matrices, atomics, pointers, arrays, structs,
  images, samplers, binding arrays.
- **Expressions**: literals, constants, composition, access, load, arithmetic,
  the math functions, texture sampling and queries, conversions.
- **Statements**: emit, block, if, switch, loop, break, continue, return,
  discard, barriers, store, call, atomics.

Each function carries the type of every expression and, when it is a pointer,
the address space it points into. A back end needs both: `x[i]` addresses an
array and `x.y` a struct member, and the expression itself does not say which.

## Diagnostics

`parse` returns the module or one diagnostic: a message, a span, and the line
and column a reader would point at.

```mbt check
///|
test {
  let result = @compile.parse("fn f() { let x = ; }")
  assert_eq(result is Err(_), true)
}
```

Validation reports the declaration at fault: the function, the global or the
type, plus a message naming the rule.

## Conformance

The snapshot corpus is the WGSL test suite of another compiler, transcribed:
74 shaders that come with a recorded WGSL round-trip output. Each case is read,
validated and written back, and the text is compared with the recording byte for
byte. `scripts/gen_snapshot_corpus.py` embeds the corpus; the replay lives in
`moonnaga/conformance`.

**Identical: 4 of 74.** The four that agree are `array-in-function-return-type`,
`empty`, `empty-if` and `multiview`. The rest split into two groups.

Refused, 24 cases — the front end stops before writing anything:

| Reason | Cases |
|:--|:--|
| `atomicCompareExchangeWeak` is not implemented | `abstract-types-atomic`, `atomicOps`, `atomicOps-int64` |
| `textureAtomicMax` and the other texture atomics are not implemented | `atomicTexture`, `atomicTexture-int64` |
| `atomicCompareExchangeWeak` in a longer expression | `atomicCompareExchange`, `atomicCompareExchange-int64` |
| A struct-typed alias used as a constructor (`Vec2`, `FVec3`) | `module-scope`, `type-alias` |
| An alias to a matrix used as a constructor (`mat4x3f`) | `operators` |
| `vec2h`, `modf`, `subgroupBarrier`, `textureSampleBaseClampToEdge` | `f16`, `math-functions`, `subgroup-operations`, `image`, `texture-external` |
| A pointer argument in a call expression | `pointer-function-arg`, `access` |
| A matrix constructor whose arguments are neither all columns nor all scalars | `constructors` |
| `const_assert` over `select`, which the folder does not evaluate | `select` |
| A `continue` or `break` inside a `continuing` block that reads a variable of the outer loop body | `break-if` |
| A `let` whose initialiser is a compound expression the parser rejects | `abstract-types-var` |

Differed, 46 cases — both sides produce a module, the text differs. The causes
are structural rather than semantic:

| Cause | Why the text differs |
|:--|:--|
| Constant folding | The recording has `const` initialisers folded through, and array lengths replaced with literals; this front end keeps the expression the source wrote |
| Expression ordering | The recording hoists every side-effecting expression into `let _eN` temporaries; this writer inlines a pure expression at each use |
| Name disambiguation | Both rename a second `uv` to `uv_1`, but the counters differ once a temporary is introduced on one side only |
| Attribute layout | The recording puts `@vertex` on a line of its own with a trailing space; this writer does the same, but a one-element `@workgroup_size(64)` is written `(64, 1, 1)` here |
| Declaration order | The recording emits structs, then constants, then globals, then functions; so does this writer, but the recording first drops what nothing refers to |

None of these change what a driver would run, and none is a difference in
acceptance: every case the front end accepts produces a module that this
library's own validator accepts.

## SPIR-V

`moonnaga/back/spv` writes SPIR-V 1.3. The output of the shipped example passes
`spirv-val --target-env vulkan1.1`; the CI workflow runs that check on every
push for the shaders the examples compile.

What the writer covers: scalar, vector, matrix and struct types, buffers in the
uniform and storage spaces (wrapping a bare array in a struct, which Vulkan
requires), constants, access chains, loads, stores, arithmetic, comparisons,
selections, the GLSL.std.450 math functions, function calls, structured control
flow, entry point interfaces (arguments read from and results written to global
variables, since a Vulkan entry point takes no parameters).

What it refuses, by name, rather than guessing: atomics, `textureStore`,
derivatives, `arrayLength`, workgroup uniform loads, pipeline constants and
binding arrays.

## Examples

| Example | What it shows |
|:--|:--|
| `src/examples/01-compile` | read, validate and write back one compute shader |
| `src/examples/02-spirv` | the same shader as a SPIR-V binary, printed as hex |

```sh
moon run src/examples/01-compile
moon run src/examples/02-spirv | xxd -r -p > add.spv
spirv-val add.spv
```

## Limits

- No GLSL or HLSL front end, and no SPIR-V front end: nothing in the stack
  produces those, and the WebGPU API takes WGSL only.
- The MSL and HLSL writers are not here yet; the representation and the SPIR-V
  writer are what the native backends of `moonwgpu` need first.
- Sampled texture types assume `f32` texels; an integer texture bound through a
  sampled handle is not distinguished yet.

## Licence

Apache-2.0. See `LICENSE`.
