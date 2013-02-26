require 'parser/adsl_ast'

class ADSL::ADSLParser
macro
rule
  \/\/[^\n\z]*                       # comment, no action
  \#[^\n\z]*                         # comment, no action
  \/\*(?:[^\*]*(?:\*+[^\/]+)?)*\*\/  # comment, no action
  class\b        { [:class, lineno] }
  extends\b      { [:extends, lineno] }
  inverseof\b    { [:inverseof, lineno] }
  create\b       { [:create, lineno] }
  delete\b       { [:delete, lineno] }
  foreach\b      { [:foreach, lineno] }
  either\b       { [:either, lineno] }
  action\b       { [:action, lineno] }
  or\b           { [:or, lineno] }
  subset\b       { [:subset, lineno] }
  oneof\b        { [:oneof, lineno] }
  \.\s*all\b     { [:dotall, lineno] }
  forall\b       { [:forall, lineno] }
  exists\b       { [:exists, lineno] }
  in\b           { [:in, lineno] }
  invariant\b    { [:invariant, lineno] }
  true\b         { [:true, lineno] }
  false\b        { [:false, lineno] }
  !=             { [text, lineno] }
  !|not\b        { [:not, lineno] }
  and\b          { [:and, lineno] }
  equal\b        { [:equal, lineno] }
  equiv\b        { [:equiv, lineno] }
  empty\b        { [:empty, lineno] }
  implies\b      { [:implies, lineno] }
  \.\.           { [text, lineno] }
  [{}:\(\)\.,]   { [text, lineno] }
  \+=            { [text, lineno] }
  \-=            { [text, lineno] }
  ==             { [text, lineno] }
  <=>            { [text, lineno] }
  <=             { [text, lineno] }
  =>             { [text, lineno] }
  =              { [text, lineno] }
  \+             { [text, lineno] }
  [01]           { [text, lineno] }
  \w+            { [:IDENT, ADSLIdent.new(:lineno => lineno, :text => text)] }
  \s              # blank, no action
  .              { [:unknown_symbol, [text, lineno]] }
end