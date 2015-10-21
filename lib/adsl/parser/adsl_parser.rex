require 'adsl/parser/ast_nodes'
require 'adsl/util/numeric_extensions'

class ADSL::Parser::ADSLParser
macro
rule
  \/\/[^\n\z]*                       # comment, no action
  \#[^\n\z]*                         # comment, no action
  \/\*(?:[^\*]*(?:\*+[^\/]+)?)*\*\/  # comment, no action
  authenticable\b   { [:authenticable, lineno] }
  usergroup\b       { [:usergroup, lineno] }
  class\b           { [:class, lineno] }
  extends\b         { [:extends, lineno] }
  inverseof\b       { [:inverseof, lineno] }
  create\b          { [:create, lineno] }
  derefcreate\b     { [:derefcreate, lineno] }
  delete\b          { [:delete, lineno] }
  foreach\b         { [:foreach, lineno] }
  flatforeach\b     { [:flatforeach, lineno] }
  unflatforeach\b   { [:unflatforeach, lineno] }
  currentuser\b     { [:currentuser, lineno] }
  inusergroup\b     { [:inusergroup, lineno] }
  allofusergroup\b  { [:allofusergroup, lineno] }
  raise\b           { [:raize, lineno] }
  foreach\b         { [:foreach, lineno] }
  either\b          { [:either, lineno] }
  if\b              { [:if, lineno] }
  else\b            { [:else, lineno] }
  action\b          { [:action, lineno] }
  or\b              { [:or, lineno] }
  xor\b             { [:xor, lineno] }
  subset\b          { [:subset, lineno] }
  oneof\b           { [:oneof, lineno] }
  tryoneof\b        { [:tryoneof, lineno] }
  allof\b           { [:allof, lineno] }
  forall\b          { [:forall, lineno] }
  exists\b          { [:exists, lineno] }
  in\b              { [:in, lineno] }
  invariant\b       { [:invariant, lineno] }
  rule\b            { [:roole, lineno] }
  true\b            { [:true, lineno] }
  false\b           { [:false, lineno] }
  !=                { [text, lineno] }
  (?:!|not)\b       { [:not, lineno] }
  and\b             { [:and, lineno] }
  equal\b           { [:equal, lineno] }
  pickoneexpr\b     { [:pickoneexpr, lineno] }
  empty\b           { [:empty, lineno] }
  isempty\b         { [:isempty, lineno] }
  implies\b         { [:implies, lineno] }
  unknown\b         { [:unknown, lineno] }
  permit\b          { [:permit, lineno] }
  permitted\b       { [:permitted, lineno] }
  permittedbytype\b { [:permittedbytype, lineno] }
  read\b            { [:read, lineno] }
  edit\b            { [:edit, lineno] }
  \.\.              { [text, lineno] }
  [{}:\(\)\.,]      { [text, lineno] }
  \+=               { [text, lineno] }
  \-=               { [text, lineno] }
  ==                { [text, lineno] }
  <=>               { [text, lineno] }
  <=                { [text, lineno] }
  =>                { [text, lineno] }
  =                 { [text, lineno] }
  \+                { [text, lineno] }
  \*                { [text, lineno] }
  [0-9]+(?:\.[0-9]+)?                        { [:NUMBER, { :value => text.to_f,   :lineno => lineno }] }
  ((?<![\\])['"])((?:.(?!(?<![\\])\1))*.?)\1 { [:STRING, { :value => text[1..-2], :lineno => lineno }] }
  (?:int|string|real|decimal|bool)\b         { [:BASIC_TYPE, [text, lineno]] }
  `(?:[^\\]*(?:\\[^`])?)*`                   { [:JS, {:js => text, :lineno => lineno}] }
  \w+             { [:IDENT, ADSL::Parser::ASTIdent.new(:lineno => lineno, :text => text)] }
  \s               # blank, no action
  .               { [:unknown_symbol, [text, lineno]] }
end
