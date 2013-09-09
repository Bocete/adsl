require 'test/unit'
require 'adsl/parser/ast_nodes'
require 'set'

class ADSL::Parser::AstNodesTest < Test::Unit::TestCase
  include ADSL::Parser

  def test__statements_are_statements
    all_nodes = ADSL::Parser.constants.map{ |c| ADSL::Parser.const_get c }.select{ |c| c < ADSL::Parser::ASTNode }
    statements = [:dummy_stmt, :assignment, :create_tup, :delete_tup, :set_tup, :delete_obj, :block, :for_each, :either, :objset_stmt, :declare_var]
    statements = statements.map{ |c| ADSL::Parser.const_get "AST#{c.to_s.camelize}" }
    difference = Set[*statements] ^ Set[*all_nodes.select{ |c| c.is_statement? }]
    assert difference.empty?
  end

  def test__create_objset_has_transitive_sideeffects
    assert ASTCreateObjset.new.objset_has_side_effects?

    assert_false ASTSubset.new.objset_has_side_effects?
    assert ASTSubset.new(:objset => ASTCreateObjset.new).objset_has_side_effects?

    assert_false ASTUnion.new.objset_has_side_effects?
    assert_false ASTUnion.new(:objsets => [
      ASTSubset.new, ASTSubset.new
    ]).objset_has_side_effects?
    assert ASTUnion.new(:objsets => [
      ASTSubset.new, ASTSubset.new, ASTCreateObjset.new
    ]).objset_has_side_effects?
  end

  def test__block_optimize__merges_nested_blocks
    block = ASTBlock.new(:statements => [
      ASTBlock.new(:statements => [
        ASTAssignment.new(:objset => 1),
        ASTAssignment.new(:objset => 2)
      ]),
      ASTAssignment.new(:objset => 3),
      ASTBlock.new(:statements => [
        ASTAssignment.new(:objset => 4),
        ASTBlock.new(:statements => [
          ASTAssignment.new(:objset => 5),
          ASTAssignment.new(:objset => 6)
        ]),
        ASTAssignment.new(:objset => 7)
      ])
    ])
    
    block = block.optimize

    assert_equal 7, block.statements.length
    7.times do |i|
      assert_equal i+1, block.statements[i].objset
    end
  end

  def test__block_optimize__remove_noop_objset_stmts
    block = ASTBlock.new(:statements => [
      ASTAssignment.new(:objset => 1),
      ASTObjsetStmt.new(:objset => ASTEmptyObjset.new),
      ASTAssignment.new(:objset => 2),
      ASTAssignment.new(:objset => 3),
      ASTObjsetStmt.new(:objset => ASTEmptyObjset.new)
    ])

    block = block.optimize
    
    assert_equal 3, block.statements.length
    3.times do |i|
      stmt = block.statements[i]
      assert_equal ASTAssignment, stmt.class
      assert_equal i+1, stmt.objset
    end
  end

  def test__block_optimize__removes_dummy_stmts
    block = ASTBlock.new(:statements => [
      ASTAssignment.new(:objset => 1),
      ASTDummyStmt.new(),
      ASTAssignment.new(:objset => 2),
      ASTDummyStmt.new()
    ])

    block = block.optimize
    
    assert_equal 2, block.statements.length
    2.times do |i|
      stmt = block.statements[i]
      assert_equal ASTAssignment, stmt.class
      assert_equal i+1, stmt.objset
    end
  end

  def test__either_optimize__merges_nested_eithers
    either = ASTEither.new(:blocks => [
      ASTBlock.new(:statements => [ASTEither.new(:blocks => [
        ASTBlock.new(:statements => [
          ASTAssignment.new(:objset => 1),
          ASTAssignment.new(:objset => 2)
        ]),
        ASTBlock.new(:statements => [
          ASTAssignment.new(:objset => 3),
          ASTAssignment.new(:objset => 4)
        ]),
        ASTBlock.new(:statements => [
          ASTEither.new(:blocks => [
            ASTBlock.new(:statements => [
              ASTAssignment.new(:objset => 5)
            ])
          ])
        ])
      ])]),
      ASTBlock.new(:statements => [
        ASTAssignment.new(:objset => 6)
      ]),
    ])
    
    either = either.optimize

    assert_equal 4, either.blocks.length
    assert_equal [1, 2], either.blocks[0].statements.map(&:objset)
    assert_equal [3, 4], either.blocks[1].statements.map(&:objset)
    assert_equal [5], either.blocks[2].statements.map(&:objset)
    assert_equal [6], either.blocks[3].statements.map(&:objset)
  end

  def test__action_optimize__removes_root_either_empty_options
    action = ASTAction.new(:block => ASTBlock.new(:statements => [
      ASTEither.new(:blocks => [
        ASTBlock.new(:statements => []),
        ASTBlock.new(:statements => [
          ASTEither.new(:blocks => [
            ASTBlock.new(:statements => [ASTDeleteObj.new(:objset => 1)]),
            ASTBlock.new(:statements => [ASTDeleteObj.new(:objset => 2)])
          ])
        ]),
        ASTBlock.new(:statements => [])
      ])
    ]))

    action = action.optimize

    assert_equal 1, action.block.statements.length
    either = action.block.statements.first
    assert_equal ASTEither, either.class

    assert_equal 2, either.blocks.length
    2.times do |i|
      assert_equal 1, either.blocks[i].statements.length
      assert_equal i+1, either.blocks[i].statements.first.objset
    end
  end

  def test__action_optimize__removes_root_either_if_only_one_option
    action = ASTAction.new(:block => ASTBlock.new(:statements => [
      ASTEither.new(:blocks => [
        ASTBlock.new(:statements => []),
        ASTBlock.new(:statements => [
          ASTEither.new(:blocks => [
            ASTBlock.new(:statements => [ASTDeleteObj.new(:objset => ASTDummyObjset.new(:type => 1))]),
            ASTBlock.new(:statements => [])
          ])
        ]),
        ASTBlock.new(:statements => [])
      ])
    ]))

    action = action.optimize

    assert_equal 1, action.block.statements.length
    assert_equal ASTDeleteObj, action.block.statements.first.class
  end

  def test__equality
    assert ASTIdent.new(:text => 'asd') == ASTIdent.new(:text => 'asd')
    assert_false ASTIdent.new(:text => 'asd') == ASTIdent.new(:text => :asd)
    assert(
      ASTSubset.new(:objset => ASTAllOf.new(:class_name => 'asd')) ==
      ASTSubset.new(:objset => ASTAllOf.new(:class_name => 'asd'))
    )
    assert_false(
      ASTSubset.new(:objset => ASTAllOf.new(:class_name => 'asd')) ==
      ASTSubset.new(:objset => ASTAllOf.new(:class_name => :asd))
    )
    assert_false ASTSubset.new == nil
    assert ASTAnd.new(:subformulae => [1, 2, 3, nil, ASTIdent.new]) == ASTAnd.new(:subformulae => [1, 2, 3, nil, ASTIdent.new])
    assert_false ASTAnd.new(:subformulae => [1, 2, 3, 4, ASTIdent.new]) == ASTAnd.new(:subformulae => [1, 2, 3, nil, ASTIdent.new])
    assert_false(
      ASTAnd.new(:subformulae => [1, 2, 3, nil, ASTIdent.new(:text => '')]) ==
      ASTAnd.new(:subformulae => [1, 2, 3, nil, ASTIdent.new])
    )
    assert ASTDeleteObj.new == ASTDeleteObj.new
    assert ASTDeleteObj.new.eql?(ASTDeleteObj.new)
    assert ASTDeleteObj.new.hash == ASTDeleteObj.new.hash
  end

  def test__block_replace__replaces_the_instance
    ast_node = ASTSubset.new(:objset => ASTAllOf.new(:class_name => ASTIdent.new(:text => :text)))
    replaced = ast_node.block_replace do |node|
      next unless node.is_a? ASTIdent
      ASTIdent.new :text => 'new_text'
    end
    assert_equal ASTSubset,  replaced.class
    assert_equal ASTAllOf,   replaced.objset.class
    assert_equal ASTIdent,   replaced.objset.class_name.class
    assert_equal 'new_text', replaced.objset.class_name.text
  end

  def test__action_optimize__prepends_instance_and_class_variables
    action = ASTAction.new(:block => ASTBlock.new(:statements => [
      ASTEither.new(:blocks => [
        ASTBlock.new(:statements => []),
        ASTBlock.new(:statements => [
          ASTBlock.new(:statements => [
            ASTBlock.new(:statements => [
              ASTAssignment.new(:objset => ASTVariable.new(:var_name => ASTIdent.new(:text => 'kme')))
            ]),
            ASTBlock.new(:statements => [
              ASTAssignment.new(:objset => ASTVariable.new(:var_name => ASTIdent.new(:text => 'at__blahblah')))
            ]),
            ASTBlock.new(:statements => [])
          ])
        ]),
        ASTBlock.new(:statements => [])
      ]),
      ASTDeleteObj.new
    ]))

    action = action.optimize
    action.prepend_global_variables_by_signatures /^at__.*$/, /^atat__.*$/
    assert_equal 3, action.block.statements.length

    assert_equal ASTAssignment,  action.block.statements[0].class
    assert_equal 'at__blahblah', action.block.statements[0].var_name.text
    assert_equal ASTEmptyObjset, action.block.statements[0].objset.class
   
    assert_equal ASTEither,     action.block.statements[1].class
    blocks = action.block.statements[1].blocks

    assert_equal 0,              blocks.first.statements.length
    assert_equal 2,              blocks.second.statements.length
    assert_equal ASTAssignment,  blocks.second.statements[0].class
    assert_equal 'kme',          blocks.second.statements[0].objset.var_name.text
    assert_equal ASTAssignment,  blocks.second.statements[1].class
    assert_equal 'at__blahblah', blocks.second.statements[1].objset.var_name.text
    
    assert_equal ASTDeleteObj,   action.block.statements[2].class
  end

  def test__either_optimize__unique_paths
    either = ASTEither.new(:blocks => [
      ASTBlock.new(:statements => []),
      ASTBlock.new(:statements => []),
      ASTBlock.new(:statements => [ASTDeleteObj.new(:objset => 1)]),
      ASTBlock.new(:statements => [ASTDeleteObj.new(:objset => 1)]),
      ASTBlock.new(:statements => [])
    ])

    either = either.optimize

    assert_equal 2, either.blocks.length

    assert_equal 0, either.blocks[0].statements.length
    assert_equal 1, either.blocks[1].statements.length
    assert_equal ASTDeleteObj, either.blocks[1].statements[0].class
    assert_equal 1,            either.blocks[1].statements[0].objset
  end

  def test__block_optimize__removes_last_stmts_without_sideeffects
    action = ASTAction.new(:block => ASTBlock.new(:statements => [
      ASTAssignment.new(:var_name => ASTIdent.new(:text => 'at_asdf'), :objset => ASTEmptyObjset.new),
      ASTEither.new(:blocks => [
        ASTBlock.new(:statements => []),
        ASTBlock.new(:statements => [
          ASTEither.new(:blocks => [
            ASTBlock.new(:statements => [
              ASTAssignment.new(:var_name => ASTIdent.new(:text => 'at_asdf'), :objset => ASTDummyObjset.new)
            ]),
            ASTBlock.new(:statements => [
              ASTAssignment.new(:var_name => ASTIdent.new(:text => 'at_asdf'), :objset => ASTDummyObjset.new)
            ])
          ])
        ]),
        ASTBlock.new(:statements => [
          ASTAssignment.new(:var_name => ASTIdent.new(:text => 'at_asdf'), :objset => ASTDummyObjset.new)
        ]),
        ASTBlock.new(:statements => [
          ASTAssignment.new(:var_name => ASTIdent.new(:text => 'at_asdf'), :objset => ASTCreateObjset.new)
        ])
      ])
    ]))

    action = action.optimize

    stmts = action.block.statements
    assert_equal 1,               stmts.length
    assert_equal ASTObjsetStmt,   stmts.first.class
    assert_equal ASTCreateObjset, stmts.first.objset.class
  end

  def test__adsl_ast_size
    ast = ASTBlock.new(:statements => [
      ASTAssignment.new(:var_name => ASTIdent.new(:text => 'asd'), :objset => ASTEmptyObjset.new),
      ASTDummyStmt.new(:type => :blah)
    ])
    assert_equal 5, ast.adsl_ast_size

    ast = ASTBlock.new(:statements => [])
    assert_equal 1, ast.adsl_ast_size
  end
end
