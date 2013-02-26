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
    scan_evaluate str
    do_parse
  end

  def parse(str)
    generate_ast(str).typecheck_and_resolve
  end

...end adsl_parser.racc/module_eval...
##### State transition tables begin ###

racc_action_table = [
    38,    39,    40,    41,    42,    38,    39,    40,    41,    42,
    38,    39,    40,    41,    42,    38,    39,    40,    41,    42,
    38,    39,    40,    41,    42,    32,    32,   122,   106,    33,
    35,    92,    53,    20,    22,     2,    98,    94,     3,    87,
   127,    96,    61,    94,    86,    71,     1,    44,   -37,   -37,
   129,    31,    34,   148,    54,   125,    20,    22,    99,    95,
    11,    12,    94,    14,    15,    16,    18,    19,    21,    23,
    44,    20,    22,   104,   105,    11,    12,    17,    14,    15,
    16,    18,    19,    21,    23,    44,    20,    22,   170,   171,
    11,    12,    17,    14,    15,    16,    18,    19,    21,    23,
    44,    20,    22,   120,   121,    11,    12,    17,    14,    15,
    16,    18,    19,    21,    23,     9,    20,    22,   142,   143,
    11,    12,    17,    14,    15,    16,    18,    19,    21,    23,
    44,    20,    22,   104,   105,    11,    12,    17,    14,    15,
    16,    18,    19,    21,    23,    44,    20,    22,   144,   145,
    11,    12,    17,    14,    15,    16,    18,    19,    21,    23,
    44,    20,    22,   112,   -41,    11,    12,    17,    14,    15,
    16,    18,    19,    21,    23,    44,    20,    22,    93,   115,
    11,    12,    17,    14,    15,    16,    18,    19,    21,    23,
    44,    20,    22,   -38,    92,    11,    12,    17,    14,    15,
    16,    18,    19,    21,    23,    44,    20,    22,    91,   119,
    11,    12,    17,    14,    15,    16,    18,    19,    21,    23,
    44,    20,    22,    90,   122,    11,    12,    17,    14,    15,
    16,    18,    19,    21,    23,    44,    20,    22,   124,    94,
    11,    12,    17,    14,    15,    16,    18,    19,    21,    23,
    44,    20,    22,    38,    38,    11,    12,    17,    14,    15,
    16,    18,    19,    21,    23,    44,    20,    22,   -20,    80,
    11,    12,    17,    14,    15,    16,    18,    19,    21,    23,
    44,    20,    22,    79,    61,    11,    12,    17,    14,    15,
    16,    18,    19,    21,    23,    44,   134,   135,   136,   137,
    74,    22,    17,   134,   135,   136,   137,    74,    22,   160,
    97,    74,    22,    94,   133,    74,    22,    20,    22,    20,
    22,   133,    74,    22,    85,    73,    20,    22,   131,    73,
    61,    44,    84,    44,    74,    22,    73,    20,    22,   -40,
    44,    20,    22,    74,    22,    74,    22,   141,    73,    20,
    22,    44,    74,    22,    56,    44,    55,    73,   146,    73,
    74,    22,    87,    44,    74,    22,    73,    88,     2,     2,
     2,     3,     3,     3,    73,    38,    39,    40,    73,     1,
     1,     1,    38,    39,    40,    41,    42,    38,    39,    40,
    41,    42,    38,    39,    40,    41,    42,    38,    39,    40,
    41,    42,   102,    52,   149,   104,   105,    38,    39,    40,
    41,    42,   130,   122,   151,   104,   105,    38,    39,    40,
    51,   153,    50,   155,   156,    49,    48,   159,    47,   163,
   164,    94,   165,    43,   166,    94,    37,   122,    36,    27,
   173,    26,    25,   122,    94,    94 ]

racc_action_check = [
    78,    78,    78,    78,    78,    76,    76,    76,    76,    76,
    45,    45,    45,    45,    45,   117,   117,   117,   117,   117,
   109,   109,   109,   109,   109,     9,    44,   167,    82,    10,
    10,   133,    25,    33,    33,     0,    78,   167,     0,    62,
   114,    76,    87,   114,    62,    45,     0,    33,     9,    44,
   117,     9,    10,   133,    25,   109,   145,   145,    80,    75,
   145,   145,    75,   145,   145,   145,   145,   145,   145,   145,
   145,    96,    96,   120,   120,    96,    96,   145,    96,    96,
    96,    96,    96,    96,    96,    96,    49,    49,   165,   165,
    49,    49,    96,    49,    49,    49,    49,    49,    49,    49,
    49,     1,     1,   103,   103,     1,     1,    49,     1,     1,
     1,     1,     1,     1,     1,     1,    17,    17,   126,   126,
    17,    17,     1,    17,    17,    17,    17,    17,    17,    17,
    17,    18,    18,    83,    83,    18,    18,    17,    18,    18,
    18,    18,    18,    18,    18,    18,    51,    51,   128,   128,
    51,    51,    18,    51,    51,    51,    51,    51,    51,    51,
    51,    98,    98,    89,    79,    98,    98,    51,    98,    98,
    98,    98,    98,    98,    98,    98,    42,    42,    74,    94,
    42,    42,    98,    42,    42,    42,    42,    42,    42,    42,
    42,    38,    38,    95,    73,    38,    38,    42,    38,    38,
    38,    38,    38,    38,    38,    38,    31,    31,    72,   101,
    31,    31,    38,    31,    31,    31,    31,    31,    31,    31,
    31,    88,    88,    70,   106,    88,    88,    31,    88,    88,
    88,    88,    88,    88,    88,    88,    40,    40,   107,   108,
    40,    40,    88,    40,    40,    40,    40,    40,    40,    40,
    40,    39,    39,    67,    66,    39,    39,    40,    39,    39,
    39,    39,    39,    39,    39,    39,    86,    86,    55,    53,
    86,    86,    39,    86,    86,    86,    86,    86,    86,    86,
    86,    41,    41,    52,    37,    41,    41,    86,    41,    41,
    41,    41,    41,    41,    41,    41,   122,   122,   122,   122,
   122,   122,    41,   139,   139,   139,   139,   139,   139,   148,
    77,   148,   148,    77,   122,   170,   170,    34,    34,    35,
    35,   139,    85,    85,    61,   148,    91,    91,   119,   170,
    36,    34,    61,    35,   137,   137,    85,   143,   143,    32,
    91,    43,    43,   171,   171,   163,   163,   124,   137,    47,
    47,   143,    48,    48,    27,    43,    26,   171,   131,   163,
    93,    93,    64,    47,    50,    50,    48,    64,     8,     7,
     6,     8,     7,     6,    93,    69,    69,    69,    50,     8,
     7,     6,   111,   111,   111,   111,   111,   116,   116,   116,
   116,   116,   158,   158,   158,   158,   158,    13,    13,    13,
    13,    13,    81,    24,   134,    81,    81,    57,    57,    57,
    57,    57,   118,   135,   136,   118,   118,    68,    68,    68,
    23,   138,    22,   140,   141,    21,    20,   146,    19,   149,
   150,   152,   155,    14,   160,   162,    12,   164,    11,     4,
   168,     3,     2,   173,   174,   175 ]

racc_action_pointer = [
    24,    82,   409,   408,   439,   nil,   359,   358,   357,     4,
    27,   398,   396,   391,   393,   nil,   nil,    97,   112,   388,
   386,   385,   382,   380,   359,    20,   316,   354,   nil,   nil,
   nil,   187,   295,    14,   298,   300,   297,   251,   172,   232,
   217,   262,   157,   322,     5,     4,   nil,   330,   333,    67,
   345,   127,   250,   236,   nil,   227,   nil,   401,   nil,   nil,
   nil,   299,    -3,   nil,   320,   nil,   248,   247,   411,   369,
   182,   nil,   166,   173,   138,    18,    -1,   269,    -6,   120,
    24,   367,   -13,    95,   nil,   303,   247,     9,   202,   122,
   nil,   307,   nil,   341,   146,   149,    52,   nil,   142,   nil,
   nil,   176,   nil,    67,   nil,   nil,   190,   205,   195,    14,
   nil,   376,   nil,   nil,    -1,   nil,   381,     9,   377,   295,
    35,   nil,   281,   nil,   314,   nil,    77,   nil,   107,   nil,
   nil,   345,   nil,    10,   371,   379,   381,   315,   386,   288,
   379,   382,   nil,   318,   nil,    37,   394,   nil,   292,   382,
   420,   nil,   387,   nil,   nil,   399,   nil,   nil,   386,   nil,
   401,   nil,   391,   326,   403,    43,   nil,    -7,   430,   nil,
   296,   324,   nil,   409,   400,   401,   nil ]

racc_action_default = [
    -5,   -76,   -76,   -76,   -76,    -1,    -5,    -5,    -5,   -42,
   -76,   -76,   -76,   -46,   -76,   -63,   -64,   -76,   -76,   -76,
   -76,   -76,   -76,   -76,   -76,   -76,   -76,   -76,    -2,    -3,
    -4,   -76,   -44,   -76,   -76,   -76,   -76,   -76,   -76,   -76,
   -76,   -76,   -76,   -76,   -42,   -76,   -50,   -76,   -76,   -76,
   -76,   -76,   -76,   -76,    -9,   -22,   177,   -47,   -59,   -62,
   -60,   -76,   -76,   -67,   -71,   -53,   -55,   -54,   -51,   -52,
   -76,   -56,   -76,   -37,   -76,   -76,   -76,   -76,   -76,   -45,
   -76,   -76,   -76,   -76,   -68,   -76,   -76,   -76,   -76,   -76,
   -65,   -76,   -40,   -76,   -76,   -43,   -76,   -39,   -76,    -9,
    -8,   -76,    -6,   -11,   -14,   -15,   -76,   -76,   -69,   -76,
   -66,   -70,   -49,   -75,   -76,   -41,   -73,   -76,   -76,   -76,
   -76,   -13,   -25,   -18,   -76,   -48,   -76,   -38,   -76,   -58,
    -7,   -17,   -12,   -37,   -76,   -76,   -76,   -76,   -76,   -25,
   -76,   -19,   -61,   -76,   -57,   -76,   -76,   -10,   -76,   -76,
   -76,   -27,   -28,   -23,   -24,   -76,   -21,   -74,   -72,   -16,
   -76,   -26,   -34,   -76,   -76,   -41,   -33,   -76,   -32,   -36,
   -76,   -76,   -31,   -76,   -29,   -30,   -35 ]

racc_goto_table = [
    13,    58,    59,    60,   123,   138,    81,    75,   161,    77,
    82,    70,     5,    62,    64,    72,    45,    46,    28,    29,
    30,    83,   154,   132,   168,   147,   107,     4,    89,   128,
    57,   126,   110,   150,   nil,   nil,   nil,    65,    66,    67,
    68,    69,   nil,   nil,   108,   nil,   nil,   nil,    76,   nil,
    78,   118,   114,   nil,   nil,   nil,   nil,   nil,   nil,   113,
   nil,   nil,   169,   nil,   nil,   172,   nil,   nil,   nil,   nil,
   nil,   176,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,   140,   nil,   nil,   nil,   109,   nil,   111,   nil,   nil,
   nil,   nil,   nil,   nil,   nil,   116,   152,   117,   140,   nil,
   nil,   nil,   nil,   nil,   nil,   nil,   nil,   162,   nil,   nil,
   nil,   157,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,   nil,   167,   nil,   nil,   nil,   nil,   nil,   nil,   174,
   175,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,   nil,   nil,   nil,   158 ]

racc_goto_check = [
    20,    19,    19,    19,    12,    14,     6,    17,    16,    17,
    11,    19,     2,    21,    21,    19,    20,    20,     2,     2,
     2,    13,    14,    10,    18,     9,     8,     1,    22,    23,
    20,    24,    25,    12,   nil,   nil,   nil,    20,    20,    20,
    20,    20,   nil,   nil,    17,   nil,   nil,   nil,    20,   nil,
    20,     6,    17,   nil,   nil,   nil,   nil,   nil,   nil,    19,
   nil,   nil,    12,   nil,   nil,    12,   nil,   nil,   nil,   nil,
   nil,    12,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,    17,   nil,   nil,   nil,    20,   nil,    20,   nil,   nil,
   nil,   nil,   nil,   nil,   nil,    20,    17,    20,    17,   nil,
   nil,   nil,   nil,   nil,   nil,   nil,   nil,    17,   nil,   nil,
   nil,    19,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,   nil,    17,   nil,   nil,   nil,   nil,   nil,   nil,    17,
    17,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,   nil,
   nil,   nil,   nil,   nil,    20 ]

racc_goto_pointer = [
   nil,    27,    12,   nil,   nil,   nil,   -48,   nil,   -57,  -106,
   -97,   -45,  -102,   -34,  -117,   nil,  -140,   -41,  -140,   -32,
    -1,   -23,   -36,   -87,   -82,   -55 ]

racc_goto_default = [
   nil,   nil,   nil,     6,     7,     8,   nil,   100,   101,   nil,
   103,   nil,   nil,   nil,   nil,   139,   nil,    24,   nil,    10,
   nil,   nil,   nil,   nil,   nil,    63 ]

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
