// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A word of a SPIR-V module. Everything in the format is one: instruction
/// headers, identifiers, literals and strings packed four bytes at a time.
pub type Word = UInt32

///|
/// What the writer could not translate. A back end refuses rather than emitting
/// something a driver would have to guess at.
#derive(Eq, Debug)
pub(all) struct Unsupported {
  feature : String
}

///|
pub suberror SpvError {
  Unsupported(Unsupported)
}

///|
pub fn[T] unsupported(feature : String) -> T raise SpvError {
  raise Unsupported({ feature, })
}

///|
/// Emits instructions into a growing list of words.
///
/// The format is positional: every instruction starts with a word whose high
/// half is how many words follow and whose low half is the opcode, and the
/// operands follow in the order the specification lists them. This type exists
/// so the callers can write `op_constant(ty, value)` and not count words.
pub(all) struct Builder {
  /// Everything the format puts after the declarations: global variables and
  /// functions, in the order they were written.
  words : Array[Word]
  /// The four sections that have to come first, kept apart because the format
  /// fixes their order and a type can be discovered halfway through a function.
  names : Array[Word]
  decorations : Array[Word]
  types : Array[Word]
  constants : Array[Word]
  mut bound : Word
  /// Where the code section starts: variables and functions go after the four
  /// fixed sections, which are assembled in front of this point.
  mut body_start : Int32
}

///|
pub fn Builder::new() -> Builder {
  {
    words: [0x07230203, 0x00010000, 0, 0, 0],
    names: [],
    decorations: [],
    types: [],
    constants: [],
    bound: 1,
    body_start: 0,
  }
}

///|
/// A fresh identifier. Zero means "no result" in the format, so numbering starts
/// at one and never hands it out.
pub fn Builder::next(self : Builder) -> Word {
  let id = self.bound
  self.bound = self.bound + 1
  id
}

///|
fn Builder::emit(self : Builder, opcode : Word, operands : Array[Word]) -> Unit {
  let count = operands.length() + 1
  let section = self.section_of(opcode)
  section.push((count.reinterpret_as_uint() << 16) | opcode)
  for operand in operands {
    section.push(operand)
  }
}

///|
/// Which section an instruction belongs to. The format fixes the order of the
/// sections, and an instruction that belongs to an earlier one has to be written
/// there even when it is discovered late.
fn Builder::section_of(self : Builder, opcode : Word) -> Array[Word] {
  if opcode >= op_type_void && opcode <= op_type_function {
    self.types
  } else if opcode >= op_constant_true && opcode <= op_constant_null {
    self.constants
  } else if opcode == op_decorate || opcode == op_member_decorate {
    self.decorations
  } else if opcode == op_name || opcode == op_member_name {
    self.names
  } else {
    self.words
  }
}

///|
/// A type or another instruction whose result carries no type of its own: the
/// first operand is the result id.
fn Builder::emit_typed(
  self : Builder,
  opcode : Word,
  operands : Array[Word],
) -> Word {
  let result = self.next()
  let all = [result]
  for operand in operands {
    all.push(operand)
  }
  self.emit(opcode, all)
  result
}

///|
/// An instruction that produces a type and a result.
fn Builder::emit_result(
  self : Builder,
  opcode : Word,
  result_type : Word,
  operands : Array[Word],
) -> Word {
  let result = self.next()
  let all = [result_type, result]
  for operand in operands {
    all.push(operand)
  }
  self.emit(opcode, all)
  result
}

///|
/// An instruction whose result id was handed out earlier, which is how a global
/// is named before its declaration is written.
fn Builder::emit_result_with_id(
  self : Builder,
  opcode : Word,
  result : Word,
  result_type : Word,
  operands : Array[Word],
) -> Word {
  let all = [result_type, result]
  for operand in operands {
    all.push(operand)
  }
  self.emit(opcode, all)
  result
}

///|
/// Packs a name into the words the format uses for strings: UTF-8 bytes, four to
/// a word, zero padded, at least one word.
pub fn string_words(text : String) -> Array[Word] {
  let bytes = text.to_array()
  let words = []
  // The format wants a terminator, and it takes a whole word of its own when
  // the text already fills the last one.
  let total = bytes.length() + 1
  let mut index = 0
  while index < total {
    let mut word : UInt32 = 0
    for offset in 0..<4 {
      let position = index + offset
      let byte = if position < bytes.length() {
        bytes[position].to_int().reinterpret_as_uint()
      } else {
        0
      }
      word = word | (byte << (offset * 8).to_int())
    }
    words.push(word)
    index = index + 4
  }
  words
}

///|
/// The module as bytes, in the little-endian order the format requires.

///|
/// Sets the header's version word from a version written as major * 10000 +
/// minor * 100 + patch.
pub fn Builder::set_version(self : Builder, version : Word) -> Unit {
  let major = version / 10000U
  let minor = version / 100U % 100U
  self.words[1] = (major << 16) | (minor << 8)
}

///|
pub fn Builder::start_body(self : Builder) -> Unit {
  self.body_start = self.words.length()
}

///|
pub fn Builder::to_bytes(self : Builder) -> Array[Byte] {
  let bytes = []
  let all = []
  for index in 0..<self.body_start.to_int() {
    all.push(self.words[index])
  }
  all.append(self.names)
  all.append(self.decorations)
  all.append(self.types)
  all.append(self.constants)
  for index in self.body_start.to_int()..<self.words.length() {
    all.push(self.words[index])
  }
  for index in 0..<all.length() {
    let word = if index == 3 { self.bound } else { all[index] }
    bytes.push((word & 0xFF).to_byte())
    bytes.push(((word >> 8) & 0xFF).to_byte())
    bytes.push(((word >> 16) & 0xFF).to_byte())
    bytes.push(((word >> 24) & 0xFF).to_byte())
  }
  bytes
}

///|
/// The opcodes this writer emits, named as the specification names them.
pub let op_nop : Word = 0

///|
pub let op_name : Word = 5

///|
pub let op_member_name : Word = 6

///|
pub let op_ext_inst_import : Word = 11

///|
pub let op_ext_inst : Word = 12

///|
pub let op_memory_model : Word = 14

///|
pub let op_entry_point : Word = 15

///|
pub let op_execution_mode : Word = 16

///|
pub let op_capability : Word = 17

///|
pub let op_type_void : Word = 19

///|
pub let op_type_bool : Word = 20

///|
pub let op_type_int : Word = 21

///|
pub let op_type_float : Word = 22

///|
pub let op_type_vector : Word = 23

///|
pub let op_type_matrix : Word = 24

///|
pub let op_type_image : Word = 25

///|
pub let op_type_sampler : Word = 26

///|
pub let op_type_sampled_image : Word = 27

///|
pub let op_type_runtime_array : Word = 29

///|
pub let op_type_array : Word = 28

///|
pub let op_type_struct : Word = 30

///|
pub let op_type_pointer : Word = 32

///|
pub let op_type_function : Word = 33

///|
pub let op_constant_true : Word = 41

///|
pub let op_constant_false : Word = 42

///|
pub let op_constant : Word = 43

///|
pub let op_constant_composite : Word = 44

///|
pub let op_constant_null : Word = 46

///|
pub let op_function : Word = 54

///|
pub let op_function_parameter : Word = 55

///|
pub let op_function_end : Word = 56

///|
pub let op_function_call : Word = 57

///|
pub let op_variable : Word = 59

///|
pub let op_load : Word = 61

///|
pub let op_store : Word = 62

///|
pub let op_access_chain : Word = 65

///|
pub let op_in_bounds_access_chain : Word = 66

///|
pub let op_decorate : Word = 71

///|
pub let op_member_decorate : Word = 72

///|
pub let op_vector_extract_dynamic : Word = 77

///|
pub let op_composite_construct : Word = 80

///|
pub let op_composite_extract : Word = 81

///|
pub let op_vector_shuffle : Word = 79

///|
pub let op_sampled_image : Word = 86

///|
pub let op_image_sample_implicit_lod : Word = 87

///|
pub let op_image_fetch : Word = 95

///|
pub let op_image_query_size_lod : Word = 103

///|
pub let op_convert_f_to_s : Word = 110

///|
pub let op_convert_s_to_f : Word = 111

///|
pub let op_convert_u_to_f : Word = 113

///|
pub let op_convert_f_to_u : Word = 109

///|
pub let op_bitcast : Word = 124

///|
pub let op_s_negate : Word = 126

///|
pub let op_f_negate : Word = 127

///|
pub let op_i_add : Word = 128

///|
pub let op_f_add : Word = 129

///|
pub let op_i_sub : Word = 130

///|
pub let op_f_sub : Word = 131

///|
pub let op_i_mul : Word = 132

///|
pub let op_f_mul : Word = 133

///|
pub let op_u_div : Word = 134

///|
pub let op_s_div : Word = 135

///|
pub let op_f_div : Word = 136

///|
pub let op_u_mod : Word = 137

///|
pub let op_s_rem : Word = 138

///|
pub let op_f_rem : Word = 139

///|
pub let op_f_mod : Word = 141

///|
pub let op_vector_times_scalar : Word = 142

///|
pub let op_matrix_times_vector : Word = 143

///|
pub let op_vector_times_matrix : Word = 144

///|
pub let op_matrix_times_matrix : Word = 146

///|
pub let op_any : Word = 154

///|
pub let op_all : Word = 155

///|
pub let op_logical_and : Word = 166

///|
pub let op_logical_or : Word = 167

///|
pub let op_logical_not : Word = 168

///|
pub let op_select : Word = 169

///|
pub let op_i_equal : Word = 170

///|
pub let op_i_not_equal : Word = 171

///|
pub let op_u_greater_than : Word = 172

///|
pub let op_s_greater_than : Word = 173

///|
pub let op_u_less_than : Word = 177

///|
pub let op_s_less_than : Word = 178

///|
pub let op_f_ord_equal : Word = 180

///|
pub let op_f_ord_not_equal : Word = 182

///|
pub let op_f_ord_less_than : Word = 184

///|
pub let op_f_ord_greater_than : Word = 186

///|
pub let op_u_less_than_equal : Word = 194

///|
pub let op_s_less_than_equal : Word = 195

///|
pub let op_f_ord_less_than_equal : Word = 188

///|
pub let op_u_greater_than_equal : Word = 190

///|
pub let op_s_greater_than_equal : Word = 191

///|
pub let op_f_ord_greater_than_equal : Word = 192

///|
pub let op_shift_left_logical : Word = 196

///|
pub let op_shift_right_logical : Word = 197

///|
pub let op_shift_right_arithmetic : Word = 198

///|
pub let op_bitwise_and : Word = 199

///|
pub let op_bitwise_or : Word = 197

///|
pub let op_bitwise_xor : Word = 202

///|
pub let op_not : Word = 200

///|
pub let op_bit_count : Word = 205

///|
pub let op_phi : Word = 245

///|
pub let op_loop_merge : Word = 246

///|
pub let op_selection_merge : Word = 247

///|
pub let op_label : Word = 248

///|
pub let op_branch : Word = 249

///|
pub let op_branch_conditional : Word = 250

///|
pub let op_switch : Word = 251

///|
pub let op_kill : Word = 252

///|
pub let op_return : Word = 253

///|
pub let op_return_value : Word = 254

///|
pub let op_control_barrier : Word = 224

///|
pub let op_memory_barrier : Word = 225
