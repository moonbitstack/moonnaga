// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The scalar a storage texture's texels hold, read off the format's name.
fn storage_scalar(format : String) -> @moonnaga.Scalar {
  if format.has_suffix("uint") {
    @moonnaga.scalar_u32
  } else if format.has_suffix("sint") {
    @moonnaga.scalar_i32
  } else {
    @moonnaga.scalar_f32
  }
}

///|
/// The image type an expression refers to.
fn Builder::image_of(
  self : Builder,
  handle : @moonnaga.Handle,
  span : @moonnaga.Span,
) -> @moonnaga.ImageType raise Failed {
  let ty = self.type_of(handle)
  match self.shader().type_inner(ty) {
    Image(image) => image
    _ => fail("this argument is not a texture", span)
  }
}

///|
/// The type of one texel of an image.
fn Builder::texel_type(
  self : Builder,
  image : @moonnaga.ImageType,
) -> @moonnaga.Handle {
  match image.class {
    @moonnaga.Depth => self.types.scalar_type(@moonnaga.scalar_f32)
    @moonnaga.Storage(_, format) =>
      match storage_scalar(format).kind {
        @moonnaga.Uint =>
          self.types.vector_type(@moonnaga.Quad, @moonnaga.scalar_u32)
        @moonnaga.Sint =>
          self.types.vector_type(@moonnaga.Quad, @moonnaga.scalar_i32)
        _ => self.types.vector_type(@moonnaga.Quad, @moonnaga.scalar_f32)
      }
    @moonnaga.Sampling =>
      self.types.vector_type(@moonnaga.Quad, @moonnaga.scalar_f32)
  }
}

///|
/// The calls that reach a texture or an atomic, which take their result types
/// from the resource rather than from their arguments.
fn Builder::call_resource_builtin(
  self : Builder,
  name : String,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match name {
    "textureDimensions" => {
      let image = self.lower_value(args[0])
      let info = self.image_of(image, span)
      let ty = match info.dim {
        @moonnaga.D1 => self.types.scalar_type(@moonnaga.scalar_u32)
        @moonnaga.D3 =>
          self.types.vector_type(@moonnaga.Tri, @moonnaga.scalar_u32)
        _ => self.types.vector_type(@moonnaga.Bi, @moonnaga.scalar_u32)
      }
      self.emit(
        @moonnaga.ImageQuery({ image, query: @moonnaga.Size, }),
        Plain(ty),
      )
    }
    "textureNumLevels" => {
      let image = self.lower_value(args[0])
      let ty = self.types.scalar_type(@moonnaga.scalar_u32)
      self.emit(
        @moonnaga.ImageQuery({ image, query: @moonnaga.NumLevels, }),
        Plain(ty),
      )
    }
    "textureNumLayers" => {
      let image = self.lower_value(args[0])
      let ty = self.types.scalar_type(@moonnaga.scalar_u32)
      self.emit(
        @moonnaga.ImageQuery({ image, query: @moonnaga.NumLayers, }),
        Plain(ty),
      )
    }
    "textureNumSamples" => {
      let image = self.lower_value(args[0])
      let ty = self.types.scalar_type(@moonnaga.scalar_u32)
      self.emit(
        @moonnaga.ImageQuery({ image, query: @moonnaga.NumSamples, }),
        Plain(ty),
      )
    }
    "textureLoad" => self.texture_load(args, span)
    "textureStore" => self.texture_store(args, span)
    "textureSample" => self.texture_sample(@moonnaga.Auto, args, span, 3)
    "textureSampleLevel" => self.texture_sample_level(args, span)
    "textureSampleBias" => {
      let image = self.lower_value(args[0])
      let info = self.image_of(image, span)
      let sampler = self.lower_value(args[1])
      let coordinate = self.lower_value(args[2])
      let bias = self.lower_value(args[3])
      let ty = self.texel_type(info)
      let level = @moonnaga.Bias(bias)
      let (array_index, offset) = self.texture_tail(info, args, 4, span)
      self.emit(
        @moonnaga.ImageSample({
          image,
          sampler,
          gather: None,
          coordinate,
          array_index,
          offset,
          level,
          depth_ref: None,
        }),
        Plain(ty),
      )
    }
    "textureSampleGrad" => {
      let image = self.lower_value(args[0])
      let info = self.image_of(image, span)
      let sampler = self.lower_value(args[1])
      let coordinate = self.lower_value(args[2])
      let dx = self.lower_value(args[3])
      let dy = self.lower_value(args[4])
      let ty = self.texel_type(info)
      let level = @moonnaga.Gradient(dx, dy)
      let (array_index, offset) = self.texture_tail(info, args, 5, span)
      self.emit(
        @moonnaga.ImageSample({
          image,
          sampler,
          gather: None,
          coordinate,
          array_index,
          offset,
          level,
          depth_ref: None,
        }),
        Plain(ty),
      )
    }
    "textureSampleCompare" | "textureSampleCompareLevel" => {
      let image = self.lower_value(args[0])
      let sampler = self.lower_value(args[1])
      let coordinate = self.lower_value(args[2])
      let depth_ref = self.lower_value(args[3])
      let info = self.image_of(image, span)
      let ty = self.types.scalar_type(@moonnaga.scalar_f32)
      let level = if name == "textureSampleCompare" {
        @moonnaga.Auto
      } else {
        @moonnaga.Zero
      }
      let (array_index, offset) = self.texture_tail(info, args, 4, span)
      self.emit(
        @moonnaga.ImageSample({
          image,
          sampler,
          gather: None,
          coordinate,
          array_index,
          offset,
          level,
          depth_ref: Some(depth_ref),
        }),
        Plain(ty),
      )
    }
    "textureGather" => {
      // The component comes first, and may be a word or an index.
      let image = self.lower_value(args[1])
      let info = self.image_of(image, span)
      let sampler = self.lower_value(args[2])
      let coordinate = self.lower_value(args[3])
      let gather = match args[0] {
        Number(number, span) =>
          gather_component(int_of_number(number, span), span)
        _ => @moonnaga.SwizzleComponent::X
      }
      let ty = self.types.vector_type(@moonnaga.Quad, @moonnaga.scalar_f32)
      let (array_index, offset) = self.texture_tail(info, args, 4, span)
      self.emit(
        @moonnaga.ImageSample({
          image,
          sampler,
          gather: Some(gather),
          coordinate,
          array_index,
          offset,
          level: @moonnaga.Zero,
          depth_ref: None,
        }),
        Plain(ty),
      )
    }
    "textureGatherCompare" => {
      let image = self.lower_value(args[0])
      let info = self.image_of(image, span)
      let sampler = self.lower_value(args[1])
      let coordinate = self.lower_value(args[2])
      let depth_ref = self.lower_value(args[3])
      let ty = self.types.vector_type(@moonnaga.Quad, @moonnaga.scalar_f32)
      let (array_index, offset) = self.texture_tail(info, args, 4, span)
      self.emit(
        @moonnaga.ImageSample({
          image,
          sampler,
          gather: Some(@moonnaga.SwizzleComponent::X),
          coordinate,
          array_index,
          offset,
          level: @moonnaga.Zero,
          depth_ref: Some(depth_ref),
        }),
        Plain(ty),
      )
    }
    _ => self.atomic_builtin(name, args, span)
  }
}

///|
fn gather_component(
  index : Int32,
  span : @moonnaga.Span,
) -> @moonnaga.SwizzleComponent raise Failed {
  match index {
    0 => @moonnaga.SwizzleComponent::X
    1 => @moonnaga.SwizzleComponent::Y
    2 => @moonnaga.SwizzleComponent::Z
    3 => @moonnaga.SwizzleComponent::W
    _ => fail("a gather takes a component from 0 to 3", span)
  }
}

///|
/// The array index and the offset that may follow the coordinates of an arrayed
/// texture.
fn Builder::texture_tail(
  self : Builder,
  image : @moonnaga.ImageType,
  args : Array[Expr],
  start : Int32,
  span : @moonnaga.Span,
) -> (@moonnaga.Handle?, @moonnaga.Handle?) raise Failed {
  let mut index = start
  let mut array_index = None
  if image.arrayed && index.to_int() < args.length() {
    array_index = Some(self.lower_value(args[index.to_int()]))
    index = index + 1
  }
  let mut offset = None
  if index.to_int() < args.length() {
    offset = Some(self.lower_value(args[index.to_int()]))
    index = index + 1
  }
  if index.to_int() != args.length() {
    fail("too many arguments", span)
  }
  (array_index, offset)
}

///|
fn Builder::texture_sample(
  self : Builder,
  level : @moonnaga.SampleLevel,
  args : Array[Expr],
  span : @moonnaga.Span,
  tail_start : Int32,
) -> @moonnaga.Handle raise Failed {
  let image = self.lower_value(args[0])
  let info = self.image_of(image, span)
  let sampler = self.lower_value(args[1])
  let coordinate = self.lower_value(args[2])
  let ty = self.texel_type(info)
  let (array_index, offset) = self.texture_tail(info, args, tail_start, span)
  self.emit(
    @moonnaga.ImageSample({
      image,
      sampler,
      gather: None,
      coordinate,
      array_index,
      offset,
      level,
      depth_ref: None,
    }),
    Plain(ty),
  )
}

///|
fn Builder::texture_sample_level(
  self : Builder,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let image = self.lower_value(args[0])
  let info = self.image_of(image, span)
  let sampler = self.lower_value(args[1])
  let coordinate = self.lower_value(args[2])
  let level = self.lower_value(args[3])
  let ty = self.texel_type(info)
  let (array_index, offset) = self.texture_tail(info, args, 4, span)
  self.emit(
    @moonnaga.ImageSample({
      image,
      sampler,
      gather: None,
      coordinate,
      array_index,
      offset,
      level: @moonnaga.Exact(level),
      depth_ref: None,
    }),
    Plain(ty),
  )
}

///|
fn Builder::texture_load(
  self : Builder,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let image = self.lower_value(args[0])
  let info = self.image_of(image, span)
  let coordinate = self.lower_value(args[1])
  let mut index = 2
  let mut array_index = None
  if info.arrayed && index.to_int() < args.length() {
    array_index = Some(self.lower_value(args[index.to_int()]))
    index = index + 1
  }
  let mut level = None
  let mut sample = None
  if index.to_int() < args.length() {
    // A multisampled texture takes a sample index, any other a level.
    match info.class {
      @moonnaga.Storage(_, _) => ()
      _ => {
        let handle = self.lower_value(args[index.to_int()])
        level = Some(handle)
      }
    }
    index = index + 1
  }
  if index.to_int() < args.length() {
    sample = Some(self.lower_value(args[index.to_int()]))
    index = index + 1
  }
  if index.to_int() != args.length() {
    fail("too many arguments to `textureLoad`", span)
  }
  let ty = self.texel_type(info)
  self.emit(
    @moonnaga.ImageLoad({ image, coordinate, array_index, sample, level, }),
    Plain(ty),
  )
}

///|
fn Builder::texture_store(
  self : Builder,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  let image = self.lower_value(args[0])
  let info = self.image_of(image, span)
  let coordinate = self.lower_value(args[1])
  let value = self.lower_value(args[2])
  let mut array_index = None
  if info.arrayed && args.length() > 3 {
    array_index = Some(self.lower_value(args[3]))
  }
  self.emits.push(
    @moonnaga.ImageStore({ image, coordinate, array_index, value, }),
  )
  self.unit_value()
}

///|
/// The atomic operations. All but the load are statements with a result the
/// statement itself names.
fn Builder::atomic_builtin(
  self : Builder,
  name : String,
  args : Array[Expr],
  span : @moonnaga.Span,
) -> @moonnaga.Handle raise Failed {
  match name {
    "atomicLoad" => {
      let pointer = self.lower_expr(args[0])
      self.as_value(pointer)
    }
    _ => {
      let fun = match name {
        "atomicStore" => @moonnaga.AtomicFunction::AtomicExchange
        "atomicAdd" => @moonnaga.AtomicFunction::AtomicAdd
        "atomicSub" => @moonnaga.AtomicFunction::AtomicSubtract
        "atomicAnd" => @moonnaga.AtomicFunction::AtomicAnd
        "atomicOr" => @moonnaga.AtomicFunction::AtomicInclusiveOr
        "atomicXor" => @moonnaga.AtomicFunction::AtomicExclusiveOr
        "atomicMin" => @moonnaga.AtomicFunction::AtomicMin
        "atomicMax" => @moonnaga.AtomicFunction::AtomicMax
        "atomicExchange" => @moonnaga.AtomicFunction::AtomicExchange
        _ => fail("`\{name}` is not a function this shader declares", span)
      }
      let pointer = self.lower_expr(args[0])
      let value = self.lower_value(args[1])
      let ty = self.type_of(pointer)
      let result = self.emit(
        @moonnaga.AtomicResult({ ty, comparison: false, }),
        Plain(ty),
      )
      self.emits.push(@moonnaga.Atomic({ fun, pointer, value, result, }))
      match name {
        "atomicStore" =>
          // The store has no result the source can use.
          self.unit_value()
        _ => result
      }
    }
  }
}
