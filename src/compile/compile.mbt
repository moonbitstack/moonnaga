// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads WGSL into a module, or says where it stopped reading.
pub fn parse(
  source : StringView,
) -> Result[@moonnaga.Module, @front.ParseError] {
  @front.parse(source)
}

///|
/// Checks a module against the language and the capabilities a device offers.
pub fn validate(
  shader : @moonnaga.Module,
  capabilities~ : @valid.Capabilities = @valid.capabilities_default,
) -> Result[@valid.ModuleInfo, @valid.ValidationError] {
  @valid.validate(shader, capabilities~)
}

///|
/// Writes a module back as WGSL.
pub fn write_wgsl(shader : @moonnaga.Module) -> String {
  @text.write_module(shader)
}

///|
/// Writes a module as a SPIR-V binary.
pub fn write_spirv(
  shader : @moonnaga.Module,
  info : @valid.ModuleInfo,
) -> Array[Byte] raise @spv.SpvError {
  @spv.write_module(shader, info)
}
