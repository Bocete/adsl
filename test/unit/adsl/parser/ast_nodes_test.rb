require 'test/unit'
require 'adsl/parser/ast_nodes'
require 'set'

class ADSL::Parser::AstNodesTest < Test::Unit::TestCase
  include ADSL::Parser

  def test__statements_are_statements
    all_nodes = ADSL::Parser.constants.map{ |c| ADSL::Parser.const_get c }.select{ |c| c < ADSL::Parser::ASTNode }
    statements = [:assignment, :create_tup, :delete_tup, :set_tup, :delete_obj, :block, :for_each, :either, :objset_stmt]
    statements = statements.map{ |c| ADSL::Parser.const_get "AST#{c.to_s.camelize}" }
    difference = Set[*statements] ^ Set[*all_nodes.select{ |c| c.is_statement? }]
    assert difference.empty?
  end

  def test__only_create_objset_has_sideeffects
    all_nodes = ADSL::Parser.constants.map{ |c| ADSL::Parser.const_get c }.select{ |c| c < ADSL::Parser::ASTNode }
    nodes = [:create_objset]
    nodes = nodes.map{ |c| ADSL::Parser.const_get "AST#{c.to_s.camelize}" }
    difference = Set[*nodes] ^ Set[*all_nodes.select{ |c| c.objset_has_side_effects? }]
    assert difference.empty?
  end

  def test__block_optimize__merges_nested_blocks
    block = ASTBlock.new(:statements => [
      ASTBlock.new(:statements => [
        ASTDummyStmt.new(:type => 1),
        ASTDummyStmt.new(:type => 2)
      ]),
      ASTDummyStmt.new(:type => 3),
      ASTBlock.new(:statements => [
        ASTDummyStmt.new(:type => 4),
        ASTBlock.new(:statements => [
          ASTDummyStmt.new(:type => 5),
          ASTDummyStmt.new(:type => 6)
        ]),
        ASTDummyStmt.new(:type => 7)
      ])
    ])
    
    block.optimize!

    assert_equal 7, block.statements.length
    7.times do |i|
      assert_equal i+1, block.statements[i].type
    end
  end

  def test__block_optimize__remove_noop_objset_stmts
    block = ASTBlock.new(:statements => [
      ASTDummyStmt.new(:type => 1),
      ASTObjsetStmt.new(:objset => ASTEmptyObjset.new),
      ASTDummyStmt.new(:type => 2),
      ASTDummyStmt.new(:type => 3),
      ASTObjsetStmt.new(:objset => ASTEmptyObjset.new)
    ])

    block.optimize!
    
    assert_equal 3, block.statements.length
    3.times do |i|
      stmt = block.statements[i]
      assert_equal ASTDummyStmt, stmt.class
      assert_equal i+1, stmt.type
    end
  end

  def test__either_optimize__merges_nested_eithers
    either = ASTEither.new(:blocks => [
      ASTBlock.new(:statements => [ASTEither.new(:blocks => [
        ASTBlock.new(:statements => [
          ASTDummyStmt.new(:type => 1),
          ASTDummyStmt.new(:type => 2)
        ]),
        ASTBlock.new(:statements => [
          ASTDummyStmt.new(:type => 3),
          ASTDummyStmt.new(:type => 4)
        ]),
        ASTBlock.new(:statements => [
          ASTEither.new(:blocks => [
            ASTBlock.new(:statements => [
              ASTDummyStmt.new(:type => 5)
            ])
          ])
        ])
      ])]),
      ASTBlock.new(:statements => [
        ASTDummyStmt.new(:type => 6)
      ]),
    ])
    
    either.optimize!

    assert_equal 4, either.blocks.length
    assert_equal [1, 2], either.blocks[0].statements.map(&:type)
    assert_equal [3, 4], either.blocks[1].statements.map(&:type)
    assert_equal [5], either.blocks[2].statements.map(&:type)
    assert_equal [6], either.blocks[3].statements.map(&:type)
  end

  def test__action_optimize__removes_root_either_empty_options
    action = ASTAction.new(:block => ASTBlock.new(:statements => [
      ASTEither.new(:blocks => [
        ASTBlock.new(:statements => []),
        ASTBlock.new(:statements => [
          ASTEither.new(:blocks => [
            ASTBlock.new(:statements => [ASTDummyStmt.new(:type => 1)]),
            ASTBlock.new(:statements => [ASTDummyStmt.new(:type => 2)])
          ])
        ]),
        ASTBlock.new(:statements => [])
      ])
    ]))

    action.optimize!

    assert_equal 1, action.block.statements.length
    either = action.block.statements.first
    assert_equal ASTEither, either.class

    assert_equal 2, either.blocks.length
    2.times do |i|
      assert_equal 1, either.blocks[i].statements.length
      assert_equal i+1, either.blocks[i].statements.first.type
    end
  end

  def test__action_optimize__removes_root_either_if_only_one_option
    action = ASTAction.new(:block => ASTBlock.new(:statements => [
      ASTEither.new(:blocks => [
        ASTBlock.new(:statements => []),
        ASTBlock.new(:statements => [
          ASTEither.new(:blocks => [
            ASTBlock.new(:statements => [ASTDummyStmt.new(:type => 1)]),
            ASTBlock.new(:statements => [])
          ])
        ]),
        ASTBlock.new(:statements => [])
      ])
    ]))

    action.optimize!

    assert_equal 1, action.block.statements.length
    assert_equal ASTDummyStmt, action.block.statements.first.class
  end
end
