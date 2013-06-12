#
# DO NOT MODIFY!!!!
# This file is automatically generated by Racc 1.4.9
# from Racc grammer file "".
#

require 'racc/parser.rb'


require 'parser/adsl_parser.rex'
require 'fol/first_order_logic'

module ADSL

class ADSLParser < Racc::Parser

module_eval(<<'...end adsl_parser.racc/module_eval...', 'adsl_parser.racc', 138)

# generated by racc
  def generate_ast(str)
    scan str
    # do_parse
  end

  def parse(str)
    generate_ast(str).typecheck_and_resolve
  end

...end adsl_parser.racc/module_eval...
##### State transition tables begin ###

racc_action_table = [
    42,    44,    43,    40,    41,    42,    44,    43,    40,    41,
    42,    44,    43,    40,    41,    42,    44,    43,    40,    41,
    42,    44,    43,    40,    41,    35,    52,    53,    96,    35,
   113,    93,    33,    63,    17,     6,   105,    99,     7,    99,
    96,   104,    98,   113,   103,    76,     8,    62,   -37,    54,
   138,    36,   -37,   146,    32,   140,    16,    17,   114,    97,
    20,    21,    96,    30,    28,    29,    22,    27,    24,    25,
    47,    16,    17,   153,   154,    20,    21,    23,    30,    28,
    29,    22,    27,    24,    25,    47,    16,    17,   155,   156,
    20,    21,    23,    30,    28,    29,    22,    27,    24,    25,
    47,    16,    17,    88,    89,    20,    21,    23,    30,    28,
    29,    22,    27,    24,    25,    47,    16,    17,   167,   168,
    20,    21,    23,    30,    28,    29,    22,    27,    24,    25,
    47,    16,    17,    88,    89,    20,    21,    23,    30,    28,
    29,    22,    27,    24,    25,    15,    16,    17,   109,   110,
    20,    21,    23,    30,    28,    29,    22,    27,    24,    25,
    47,    16,    17,    74,   -38,    20,    21,    23,    30,    28,
    29,    22,    27,    24,    25,    47,    16,    17,   116,    66,
    20,    21,    23,    30,    28,    29,    22,    27,    24,    25,
    47,    16,    17,    74,   -40,    20,    21,    23,    30,    28,
    29,    22,    27,    24,    25,    47,    16,    17,   120,   -20,
    20,    21,    23,    30,    28,    29,    22,    27,    24,    25,
    47,    16,    17,    58,    56,    20,    21,    23,    30,    28,
    29,    22,    27,    24,    25,    47,    16,    17,    55,   125,
    20,    21,    23,    30,    28,    29,    22,    27,    24,    25,
    47,    16,    17,   107,   106,    20,    21,    23,    30,    28,
    29,    22,    27,    24,    25,    47,    16,    17,    51,   136,
    20,    21,    23,    30,    28,    29,    22,    27,    24,    25,
    47,    16,    17,    74,    50,    20,    21,    23,    30,    28,
    29,    22,    27,    24,    25,    47,   134,   135,   131,   132,
    63,    17,    23,   134,   135,   131,   132,    63,    17,   159,
   137,    63,    17,    96,   130,    63,    17,    63,    17,    16,
    17,   130,    16,    17,   101,    62,    16,    17,    96,    62,
    90,    62,   100,    47,    63,    17,    47,    63,    17,    91,
    47,    63,    17,    16,    17,    16,    17,    46,    62,    16,
    17,    62,    63,    17,   143,    62,   144,    47,    45,    47,
    63,    17,    42,    47,    16,    17,    62,   147,     6,     6,
     6,     7,     7,     7,    62,    42,    44,    43,    47,     8,
     8,     8,    42,    44,    43,    40,    41,    42,    44,    43,
    40,    41,   127,    39,    84,    88,    89,    88,    89,    42,
    44,    43,    40,    41,    42,    44,    43,    40,    41,    42,
    44,    43,    40,    41,    95,   149,   150,    96,    42,    44,
    43,   113,   152,    42,   -41,   157,    38,   108,   161,   162,
   163,    37,    34,   166,    96,    94,    31,   113,    93,    14,
    13,     9,   175,    96,    96,   113 ]

racc_action_check = [
    78,    78,    78,    78,    78,    77,    77,    77,    77,    77,
    49,    49,    49,    49,    49,   117,   117,   117,   117,   117,
   123,   123,   123,   123,   123,    15,    26,    26,   148,    47,
   169,   130,    13,   101,   101,     0,    78,    72,     0,    75,
   169,    77,    72,    91,    75,    49,     0,   101,    15,    26,
   117,    15,    47,   130,    13,   123,   104,   104,    92,    65,
   104,   104,    65,   104,   104,   104,   104,   104,   104,   104,
   104,   154,   154,   139,   139,   154,   154,   104,   154,   154,
   154,   154,   154,   154,   154,   154,    51,    51,   141,   141,
    51,    51,   154,    51,    51,    51,    51,    51,    51,    51,
    51,    36,    36,    60,    60,    36,    36,    51,    36,    36,
    36,    36,    36,    36,    36,    36,    50,    50,   161,   161,
    50,    50,    36,    50,    50,    50,    50,    50,    50,    50,
    50,     8,     8,   109,   109,     8,     8,    50,     8,     8,
     8,     8,     8,     8,     8,     8,    98,    98,    87,    87,
    98,    98,     8,    98,    98,    98,    98,    98,    98,    98,
    98,    44,    44,    45,    95,    44,    44,    98,    44,    44,
    44,    44,    44,    44,    44,    44,    22,    22,    96,    39,
    22,    22,    44,    22,    22,    22,    22,    22,    22,    22,
    22,    23,    23,    99,    35,    23,    23,    22,    23,    23,
    23,    23,    23,    23,    23,    23,    40,    40,   102,    34,
    40,    40,    23,    40,    40,    40,    40,    40,    40,    40,
    40,   103,   103,    33,    30,   103,   103,    40,   103,   103,
   103,   103,   103,   103,   103,   103,    42,    42,    27,   108,
    42,    42,   103,    42,    42,    42,    42,    42,    42,    42,
    42,    41,    41,    83,    82,    41,    41,    42,    41,    41,
    41,    41,    41,    41,    41,    41,   105,   105,    25,   114,
   105,   105,    41,   105,   105,   105,   105,   105,   105,   105,
   105,    43,    43,    46,    24,    43,    43,   105,    43,    43,
    43,    43,    43,    43,    43,    43,   113,   113,   113,   113,
   113,   113,    43,   129,   129,   129,   129,   129,   129,   146,
   115,   146,   146,   115,   113,    38,    38,    37,    37,    53,
    53,   129,   106,   106,    74,   146,   156,   156,   119,    38,
    58,    37,    74,    53,   168,   168,   106,   167,   167,    59,
   156,    94,    94,    54,    54,    55,    55,    21,   168,    56,
    56,   167,   132,   132,   125,    94,   128,    54,    20,    55,
   162,   162,    71,    56,    52,    52,   132,   131,     5,     4,
     3,     5,     4,     3,   162,    68,    68,    68,    52,     5,
     4,     3,    61,    61,    61,    61,    61,   164,   164,   164,
   164,   164,   111,    18,    57,   111,   111,    57,    57,   121,
   121,   121,   121,   121,   122,   122,   122,   122,   122,    19,
    19,    19,    19,    19,    64,   133,   134,    64,    67,    67,
    67,   135,   136,    70,    66,   143,    17,    86,   149,   150,
   151,    16,    14,   159,   160,    63,     9,   163,    62,     7,
     6,     1,   170,   172,   173,   175 ]

racc_action_pointer = [
    24,   441,   nil,   359,   358,   357,   407,   406,   112,   436,
   nil,   nil,   nil,    20,   392,     4,   391,   386,   349,   403,
   318,   307,   157,   172,   244,   228,    24,   198,   nil,   nil,
   184,   nil,   nil,   190,   168,   150,    82,   298,   296,   146,
   187,   232,   217,   262,   142,   130,   250,     8,   nil,     4,
    97,    67,   345,   300,   324,   326,   330,   359,   296,   298,
    65,   376,   417,   395,   373,    18,   380,   412,   369,   nil,
   417,   356,    -5,   nil,   299,    -3,   nil,    -1,    -6,   nil,
   nil,   nil,   212,   212,   nil,   nil,   394,   112,   nil,   nil,
   nil,     9,    25,   nil,   322,   120,   145,   nil,   127,   160,
   nil,    14,   167,   202,    37,   247,   303,   nil,   206,    95,
   nil,   357,   nil,   281,   236,   269,   nil,     9,   nil,   284,
   nil,   393,   398,    14,   nil,   341,   nil,   nil,   321,   288,
    10,   334,   333,   371,   383,   387,   380,   nil,   nil,    32,
   nil,    47,   nil,   392,   nil,   nil,   292,   nil,   -16,   395,
   382,   420,   nil,   nil,    52,   nil,   307,   nil,   nil,   400,
   390,    73,   341,   403,   381,   nil,   nil,   318,   315,    -4,
   432,   nil,   399,   400,   nil,   411,   nil ]

racc_action_default = [
    -5,   -76,    -1,    -5,    -5,    -5,   -76,   -76,   -76,   -76,
    -2,    -3,    -4,   -76,   -76,   -42,   -76,   -76,   -76,   -46,
   -76,   -76,   -76,   -76,   -76,   -76,   -76,   -76,   -63,   -64,
   -76,   177,    -9,   -76,   -22,   -44,   -76,   -76,   -76,   -76,
   -76,   -76,   -76,   -76,   -76,   -76,   -76,   -42,   -50,   -76,
   -76,   -76,   -76,   -76,   -76,   -76,   -76,   -76,   -76,   -76,
   -76,   -47,   -37,   -76,   -76,   -76,   -45,   -51,   -52,   -53,
   -54,   -55,   -76,   -67,   -76,   -71,   -56,   -76,   -76,   -59,
   -60,   -62,   -76,   -76,    -6,    -8,   -76,   -11,   -14,   -15,
    -9,   -76,   -76,   -40,   -76,   -43,   -76,   -39,   -76,   -76,
   -68,   -76,   -76,   -76,   -76,   -76,   -76,   -65,   -76,   -76,
   -13,   -76,   -18,   -25,   -76,   -76,   -41,   -76,   -66,   -69,
   -49,   -70,   -73,   -76,   -75,   -17,   -12,    -7,   -76,   -25,
   -37,   -76,   -76,   -76,   -76,   -76,   -19,   -38,   -48,   -76,
   -58,   -76,   -10,   -76,   -23,   -24,   -76,   -27,   -28,   -76,
   -76,   -76,   -21,   -57,   -76,   -61,   -76,   -16,   -26,   -76,
   -34,   -41,   -76,   -76,   -72,   -74,   -33,   -76,   -76,   -76,
   -32,   -36,   -29,   -30,   -31,   -76,   -35 ]

racc_goto_table = [
    19,    79,    80,    81,    82,    83,    64,    65,   112,    57,
   128,    72,    75,     2,    48,    49,    10,    11,    12,   158,
    59,    60,   126,   170,   142,    92,   145,     1,    61,   102,
   139,   141,    67,    68,    69,    70,    71,   118,   nil,   nil,
   nil,   nil,    77,    78,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,   nil,   151,   nil,   nil,   124,   nil,   nil,   nil,   nil,
   nil,   nil,   nil,   115,   nil,   nil,   nil,   111,   nil,   nil,
   119,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   171,   nil,   133,   nil,   nil,   nil,   174,   nil,   nil,   nil,
   117,   nil,   176,   nil,   nil,   121,   122,   123,   133,   nil,
   nil,   148,   nil,   nil,   nil,   165,   nil,   nil,   nil,   nil,
   nil,   nil,   nil,   nil,   nil,   160,   nil,   nil,   nil,   nil,
   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,   169,   nil,   nil,   nil,   nil,   172,   173,   nil,   nil,
   nil,   nil,   nil,   nil,   nil,   nil,   164 ]

racc_goto_check = [
    20,    19,    19,    19,    19,    19,    17,    17,    12,     6,
    14,    21,    21,     2,    20,    20,     2,     2,     2,    16,
    11,    13,    10,    18,     9,     8,    14,     1,    20,    22,
    23,    24,    20,    20,    20,    20,    20,    25,   nil,   nil,
   nil,   nil,    20,    20,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,   nil,    12,   nil,   nil,    19,   nil,   nil,   nil,   nil,
   nil,   nil,   nil,    17,   nil,   nil,   nil,     6,   nil,   nil,
    17,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
    12,   nil,    17,   nil,   nil,   nil,    12,   nil,   nil,   nil,
    20,   nil,    12,   nil,   nil,    20,    20,    20,    17,   nil,
   nil,    17,   nil,   nil,   nil,    19,   nil,   nil,   nil,   nil,
   nil,   nil,   nil,   nil,   nil,    17,   nil,   nil,   nil,   nil,
   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,    17,   nil,   nil,   nil,   nil,    17,    17,   nil,   nil,
   nil,   nil,   nil,   nil,   nil,   nil,    20 ]

racc_goto_pointer = [
   nil,    27,    13,   nil,   nil,   nil,   -23,   nil,   -35,  -101,
   -87,   -14,   -83,   -13,  -103,   nil,  -127,   -31,  -140,   -51,
    -8,   -34,   -46,   -92,   -93,   -62 ]

racc_goto_default = [
   nil,   nil,   nil,     3,     4,     5,   nil,    85,    86,   nil,
    87,   nil,   nil,   nil,   nil,   129,   nil,    18,   nil,    26,
   nil,   nil,   nil,   nil,   nil,    73 ]

racc_reduce_table = [
  0, 0, :racc_error,
  1, 49, :_reduce_1,
  2, 50, :_reduce_2,
  2, 50, :_reduce_3,
  2, 50, :_reduce_4,
  0, 50, :_reduce_5,
  5, 51, :_reduce_6,
  7, 51, :_reduce_7,
  2, 54, :_reduce_8,
  0, 54, :_reduce_9,
  4, 55, :_reduce_10,
  1, 56, :_reduce_11,
  3, 56, :_reduce_12,
  2, 56, :_reduce_13,
  1, 58, :_reduce_14,
  1, 58, :_reduce_15,
  2, 57, :_reduce_16,
  0, 57, :_reduce_17,
  6, 52, :_reduce_18,
  4, 59, :_reduce_19,
  0, 59, :_reduce_20,
  5, 61, :_reduce_21,
  0, 61, :_reduce_22,
  3, 60, :_reduce_23,
  2, 62, :_reduce_24,
  0, 62, :_reduce_25,
  3, 63, :_reduce_26,
  2, 63, :_reduce_27,
  2, 63, :_reduce_28,
  5, 63, :_reduce_29,
  5, 63, :_reduce_30,
  5, 63, :_reduce_31,
  4, 63, :_reduce_32,
  2, 64, :_reduce_33,
  1, 64, :_reduce_34,
  3, 66, :_reduce_35,
  1, 66, :_reduce_36,
  1, 65, :_reduce_37,
  4, 65, :_reduce_38,
  4, 65, :_reduce_39,
  2, 65, :_reduce_40,
  3, 65, :_reduce_41,
  1, 67, :_reduce_42,
  4, 67, :_reduce_43,
  2, 67, :_reduce_44,
  3, 67, :_reduce_45,
  2, 53, :_reduce_46,
  4, 53, :_reduce_47,
  6, 68, :_reduce_48,
  5, 68, :_reduce_49,
  2, 68, :_reduce_50,
  3, 68, :_reduce_51,
  3, 68, :_reduce_52,
  3, 68, :_reduce_53,
  3, 68, :_reduce_54,
  3, 68, :_reduce_55,
  3, 68, :_reduce_56,
  7, 68, :_reduce_57,
  6, 68, :_reduce_58,
  3, 68, :_reduce_59,
  3, 68, :_reduce_60,
  7, 68, :_reduce_61,
  3, 68, :_reduce_62,
  1, 68, :_reduce_63,
  1, 68, :_reduce_64,
  4, 68, :_reduce_65,
  3, 69, :_reduce_66,
  1, 69, :_reduce_67,
  2, 73, :_reduce_68,
  3, 73, :_reduce_69,
  2, 70, :_reduce_70,
  0, 70, :_reduce_71,
  3, 71, :_reduce_72,
  0, 71, :_reduce_73,
  3, 72, :_reduce_74,
  0, 72, :_reduce_75 ]

racc_reduce_n = 76

racc_shift_n = 177

racc_token_table = {
  false => 0,
  :error => 1,
  "==" => 2,
  "!=" => 3,
  :noassoc => 4,
  :NOT => 5,
  "<=>" => 6,
  "<=" => 7,
  "=>" => 8,
  :and => 9,
  :or => 10,
  :class => 11,
  :extends => 12,
  :inverseof => 13,
  :action => 14,
  :foreach => 15,
  :either => 16,
  :create => 17,
  :delete => 18,
  :subset => 19,
  :oneof => 20,
  :dotall => 21,
  :invariant => 22,
  :forall => 23,
  :exists => 24,
  :in => 25,
  :empty => 26,
  :true => 27,
  :false => 28,
  :not => 29,
  :equal => 30,
  :equiv => 31,
  :implies => 32,
  :IDENT => 33,
  "{" => 34,
  "}" => 35,
  ".." => 36,
  "+" => 37,
  "0" => 38,
  "1" => 39,
  "(" => 40,
  ")" => 41,
  "," => 42,
  "=" => 43,
  "." => 44,
  "+=" => 45,
  "-=" => 46,
  ":" => 47 }

racc_nt_base = 48

racc_use_result_var = true

Racc_arg = [
  racc_action_table,
  racc_action_check,
  racc_action_default,
  racc_action_pointer,
  racc_goto_table,
  racc_goto_check,
  racc_goto_default,
  racc_goto_pointer,
  racc_nt_base,
  racc_reduce_table,
  racc_token_table,
  racc_shift_n,
  racc_reduce_n,
  racc_use_result_var ]

Racc_token_to_s_table = [
  "$end",
  "error",
  "\"==\"",
  "\"!=\"",
  "noassoc",
  "NOT",
  "\"<=>\"",
  "\"<=\"",
  "\"=>\"",
  "and",
  "or",
  "class",
  "extends",
  "inverseof",
  "action",
  "foreach",
  "either",
  "create",
  "delete",
  "subset",
  "oneof",
  "dotall",
  "invariant",
  "forall",
  "exists",
  "in",
  "empty",
  "true",
  "false",
  "not",
  "equal",
  "equiv",
  "implies",
  "IDENT",
  "\"{\"",
  "\"}\"",
  "\"..\"",
  "\"+\"",
  "\"0\"",
  "\"1\"",
  "\"(\"",
  "\")\"",
  "\",\"",
  "\"=\"",
  "\".\"",
  "\"+=\"",
  "\"-=\"",
  "\":\"",
  "$start",
  "adslspec",
  "root_elems",
  "class_decl",
  "action_decl",
  "invariant_decl",
  "rel_decls",
  "rel_decl",
  "cardinality",
  "inverse_suffix",
  "card_number",
  "action_args",
  "block",
  "additional_args",
  "statements",
  "statement",
  "assignmentrhs",
  "objset",
  "eitherblocks",
  "invariant_objset",
  "formula",
  "quantifier_parameters_with_commas",
  "optional_formula",
  "additional_formulae",
  "additional_invariant_objsets",
  "quantifier_parameter" ]

Racc_debug_parser = false

##### State transition tables end #####

# reduce 0 omitted

module_eval(<<'.,.,', 'adsl_parser.racc', 11)
  def _reduce_1(val, _values, result)
     return ADSLSpec.new :lineno => lineno, :classes => val[0][0], :actions => val[0][1], :invariants => val[0][2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 13)
  def _reduce_2(val, _values, result)
     val[1][0].unshift val[0]; return val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 14)
  def _reduce_3(val, _values, result)
     val[1][1].unshift val[0]; return val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 15)
  def _reduce_4(val, _values, result)
     val[1][2].unshift val[0]; return val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 16)
  def _reduce_5(val, _values, result)
     return [[], [], []] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 19)
  def _reduce_6(val, _values, result)
     return ADSLClass.new :lineno => val[0], :name => val[1], :relations => val[3] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 21)
  def _reduce_7(val, _values, result)
     return ADSLClass.new :lineno => val[0], :name => val[1], :parent_name => val[3], :relations => val[5] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 23)
  def _reduce_8(val, _values, result)
     val[0] << val[1]; return val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 24)
  def _reduce_9(val, _values, result)
     return [] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 26)
  def _reduce_10(val, _values, result)
     return ADSLRelation.new :lineno => val[0][2], :cardinality => val[0].first(2), :to_class_name => val[1], :name => val[2], :inverse_of_name => val[3] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 28)
  def _reduce_11(val, _values, result)
     return [val[0][0], val[0][0], val[0][1]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 29)
  def _reduce_12(val, _values, result)
     return [val[0][0], val[2][0], val[0][1]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 30)
  def _reduce_13(val, _values, result)
     return [val[0][0], 1.0/0.0, val[0][1]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 32)
  def _reduce_14(val, _values, result)
     return [0, lineno] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 33)
  def _reduce_15(val, _values, result)
     return [1, lineno] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 35)
  def _reduce_16(val, _values, result)
     return val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 36)
  def _reduce_17(val, _values, result)
     return nil 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 38)
  def _reduce_18(val, _values, result)
     return ADSLAction.new(:lineno => val[0], :name => val[1], :arg_cardinalities => val[3][0], :arg_types => val[3][1], :arg_names => val[3][2], :block => val[5]) 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 40)
  def _reduce_19(val, _values, result)
     val[0][0] << val[1]; val[0][1] << val[2]; val[0][2] << val[3]; return val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 41)
  def _reduce_20(val, _values, result)
     return [[], [], []] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 43)
  def _reduce_21(val, _values, result)
     val[0][0] << val[1]; val[0][1] << val[2]; val[0][2] << val[3]; return val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 44)
  def _reduce_22(val, _values, result)
     return [[], [], []] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 46)
  def _reduce_23(val, _values, result)
     return ADSLBlock.new :lineno => val[0], :statements => val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 48)
  def _reduce_24(val, _values, result)
     val[1].unshift val[0]; return val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 49)
  def _reduce_25(val, _values, result)
     return [] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 51)
  def _reduce_26(val, _values, result)
     val[2].var_name = val[0]; return val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 52)
  def _reduce_27(val, _values, result)
     return ADSLCreateObj.new :lineno => val[0], :class_name => val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 53)
  def _reduce_28(val, _values, result)
     return ADSLDeleteObj.new :lineno => val[0], :objset => val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 54)
  def _reduce_29(val, _values, result)
     return ADSLCreateTup.new :lineno => val[0].lineno, :objset1 => val[0], :rel_name => val[2], :objset2 => val[4] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 55)
  def _reduce_30(val, _values, result)
     return ADSLDeleteTup.new :lineno => val[0].lineno, :objset1 => val[0], :rel_name => val[2], :objset2 => val[4] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 56)
  def _reduce_31(val, _values, result)
     return ADSLForEach.new :lineno => val[0], :var_name => val[1], :objset => val[3], :block => val[4] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 57)
  def _reduce_32(val, _values, result)
     val[3].unshift val[1]; return ADSLEither.new :lineno => val[0], :blocks => val[3] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 59)
  def _reduce_33(val, _values, result)
     return ADSLCreateObj.new :lineno => val[0], :class_name => val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 60)
  def _reduce_34(val, _values, result)
     return ADSLAssignment.new :lineno => val[0].lineno, :objset => val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 62)
  def _reduce_35(val, _values, result)
     val[0] << val[2]; return val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 63)
  def _reduce_36(val, _values, result)
     return [val[0]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 65)
  def _reduce_37(val, _values, result)
     return ADSLVariable.new :lineno => val[0].lineno, :var_name => val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 66)
  def _reduce_38(val, _values, result)
     return ADSLSubset.new :lineno => val[0], :objset => val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 67)
  def _reduce_39(val, _values, result)
     return ADSLOneOf.new :lineno => val[0], :objset => val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 68)
  def _reduce_40(val, _values, result)
     return ADSLAllOf.new :lineno => val[0].lineno, :class_name => val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 69)
  def _reduce_41(val, _values, result)
     return ADSLDereference.new :lineno => val[0].lineno, :objset => val[0], :rel_name => val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 71)
  def _reduce_42(val, _values, result)
     return ADSLVariable.new :lineno => val[0].lineno, :var_name => val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 72)
  def _reduce_43(val, _values, result)
     return ADSLSubset.new :lineno => val[0], :objset => val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 73)
  def _reduce_44(val, _values, result)
     return ADSLAllOf.new :lineno => val[0].lineno, :class_name => val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 74)
  def _reduce_45(val, _values, result)
     return ADSLDereference.new :lineno => val[0].lineno, :objset => val[0], :rel_name => val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 76)
  def _reduce_46(val, _values, result)
     return ADSLInvariant.new :lineno => val[0], :name => nil, :formula => val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 77)
  def _reduce_47(val, _values, result)
     return ADSLInvariant.new :lineno => val[0], :name => val[1], :formula => val[3] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 80)
  def _reduce_48(val, _values, result)
     return ADSLForAll.new :lineno => val[0], :vars => val[2], :subformula => val[4] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 82)
  def _reduce_49(val, _values, result)
     return ADSLExists.new :lineno => val[0], :vars => val[2], :subformula => val[3] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 84)
  def _reduce_50(val, _values, result)
     return ADSLNot.new :lineno => val[0], :subformula => val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 86)
  def _reduce_51(val, _values, result)
     return ADSLAnd.new :lineno => val[0].lineno, :subformulae => [val[0], val[2]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 88)
  def _reduce_52(val, _values, result)
     return ADSLOr.new :lineno => val[0].lineno, :subformulae => [val[0], val[2]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 90)
  def _reduce_53(val, _values, result)
     return ADSLEquiv.new :lineno => val[0].lineno, :subformulae => [val[0], val[2]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 92)
  def _reduce_54(val, _values, result)
     return ADSLImplies.new :lineno => val[0].lineno, :subformula1 => val[0], :subformula2 => val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 94)
  def _reduce_55(val, _values, result)
     return ADSLImplies.new :lineno => val[0].lineno, :subformula1 => val[2], :subformula2 => val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 95)
  def _reduce_56(val, _values, result)
     return val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 97)
  def _reduce_57(val, _values, result)
     return ADSLEquiv.new :lineno => val[0], :subformulae => [val[2], val[4]] + val[5] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 99)
  def _reduce_58(val, _values, result)
     return ADSLImplies.new :lineno => val[0], :subformula1 => val[2], :subformula2 => val[4] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 101)
  def _reduce_59(val, _values, result)
     return ADSLEqual.new :lineno => val[0].lineno, :objsets => [val[0], val[2]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 103)
  def _reduce_60(val, _values, result)
     return ADSLNot.new(:lineno => val[0].lineno, :subformula => ADSLEqual.new(:lineno => val[0].lineno, :objsets => [val[0], val[2]])) 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 105)
  def _reduce_61(val, _values, result)
     return ADSLEqual.new :lineno => val[0], :objsets => [val[2], val[4]] + val[5] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 106)
  def _reduce_62(val, _values, result)
     return ADSLIn.new :lineno => val[0].lineno, :objset1 => val[0], :objset2 => val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 107)
  def _reduce_63(val, _values, result)
     return ADSLBoolean.new :lineno => val[0], :bool_value => true 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 108)
  def _reduce_64(val, _values, result)
     return ADSLBoolean.new :lineno => val[0], :bool_value => false 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 109)
  def _reduce_65(val, _values, result)
     return ADSLEmpty.new :lineno => val[0], :objset => val[2] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 112)
  def _reduce_66(val, _values, result)
     val[0] << val[2]; return val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 113)
  def _reduce_67(val, _values, result)
     return [val[0]] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 115)
  def _reduce_68(val, _values, result)
     return [val[1], ADSLAllOf.new(:lineno => val[0].lineno, :class_name => val[0]), val[0].lineno] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 116)
  def _reduce_69(val, _values, result)
     return [val[0], val[2], val[0].lineno] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 118)
  def _reduce_70(val, _values, result)
     return val[1] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 119)
  def _reduce_71(val, _values, result)
     return nil 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 121)
  def _reduce_72(val, _values, result)
     val[0] << val[2]; return val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 122)
  def _reduce_73(val, _values, result)
     return [] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 124)
  def _reduce_74(val, _values, result)
     val[0] << val[2]; return val[0] 
    result
  end
.,.,

module_eval(<<'.,.,', 'adsl_parser.racc', 125)
  def _reduce_75(val, _values, result)
     return [] 
    result
  end
.,.,

def _reduce_none(val, _values, result)
  val[0]
end

end   # class ADSLParser


end
