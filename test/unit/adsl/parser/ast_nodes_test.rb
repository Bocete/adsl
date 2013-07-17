require 'test/unit'
require 'adsl/parser/ast_nodes'
require 'set'

class ADSL::Parser::AstNodesTest < Test::Unit::TestCase
  def test__statements_are_statements
    all_nodes = ADSL::Parser.constants.map{ |c| ADSL::Parser.const_get c }.select{ |c| c < ADSL::Parser::ASTNode }
    statements = [:assignment, :create_tup, :delete_tup, :set_tup, :delete_obj, :block, :for_each, :either, :objset_stmt]
    statements = statements.map{ |c| ADSL::Parser.const_get "AST#{c.to_s.camelize}" }
    difference = Set[*statements] ^ Set[*all_nodes.select{ |c| c.is_statement? }]
    assert difference.empty?
  end
end
