// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Lowers an expression that lives at module scope, where there are no locals.
fn Builder::lower_const_expr(
  self : Builder,
  expr : Expr,
) -> @moonnaga.Handle raise Failed {
  self.lower_value(expr)
}

///|
/// Reads WGSL source into a module.
///
/// The result is the module and nothing else: every rule that can be checked
/// without the feature set of a device is checked here, and the rest is left to
/// [`validate`], which is the pass a caller runs with the capabilities it has.
pub fn parse(text : StringView) -> Result[@moonnaga.Module, ParseError] {
  let source = text.to_owned()
  try {
    let unit = parse_translation_unit(source)
    Ok(build(unit))
  } catch {
    Failed(error) => {
      let location = @moonnaga.location_of(source, error.span.start)
      Err({ ..error, line: location.line, column: location.column, })
    }
  }
}
