require 'adsl/util/test_helper'
require 'adsl/lang/ast_nodes'
require 'set'

class ADSL::Lang::Parser::ASTNodesTest < ActiveSupport::TestCase
  include ADSL::Lang

  def test__create_objset_has_transitive_sideeffects
    assert ASTCreateObjset.new.has_side_effects?

    assert_false ASTSubset.new(:objset => block).has_side_effects?
    assert       ASTSubset.new(:objset => ASTCreateObjset.new).has_side_effects?

    assert_false ASTUnion.new(:objsets => []).has_side_effects?
    assert_false ASTUnion.new(:objsets => [
      ASTSubset.new, ASTSubset.new
    ]).has_side_effects?
    assert ASTUnion.new(:objsets => [
      ASTSubset.new, ASTSubset.new, ASTCreateObjset.new
    ]).has_side_effects?
  end

  def test__block_optimize__merges_nested_blocks
    block = block(
      block(
        ASTAssignment.new(:expr => 1),
        ASTAssignment.new(:expr => 2)
      ),
      ASTAssignment.new(:expr => 3),
      block(
        ASTAssignment.new(:expr => 4),
        block(
          ASTAssignment.new(:expr => 5),
          ASTAssignment.new(:expr => 6)
        ),
        ASTAssignment.new(:expr => 7)
      )
    )
    
    block = block.optimize

    assert_equal 7, block.exprs.length
    7.times do |i|
      assert_equal i+1, block.exprs[i].expr
    end
  end

  def test__block_optimize__remove_noop_objset_stmts
    block = block(
      ASTAssignment.new(:expr => 1),
      ASTEmptyObjset.new,
      ASTAssignment.new(:expr => 2),
      ASTAllOf.new,
      ASTAssignment.new(:expr => 3),
    )

    block = block.optimize
    
    assert_equal 3, block.exprs.length
    3.times do |i|
      stmt = block.exprs[i]
      assert_equal ASTAssignment, stmt.class
      assert_equal i+1,           stmt.expr
    end
  end

  def test__block_optimize__removes_flags
    block = block(
      ASTAssignment.new(:expr => 1),
      ASTFlag.new,
      ASTAssignment.new(:expr => 2),
      ASTFlag.new,
      ASTAssignment.new(:expr => 3),
    )

    block = block.optimize
    
    assert_equal 3, block.exprs.length
    3.times do |i|
      stmt = block.exprs[i]
      assert_equal ASTAssignment, stmt.class
      assert_equal i+1,           stmt.expr
    end
  end

  def test__block_optimize__removes_noops_except_last
    block = block(
      ASTAssignment.new(:expr => 1),
      ASTAllOf.new(:class_name => 'klass1'),
      ASTAssignment.new(:expr => 2),
      ASTAllOf.new(:class_name => 'klass2'),
    )

    block = block.optimize
    
    assert_equal 3, block.exprs.length
    2.times do |i|
      stmt = block.exprs[i]
      assert_equal ASTAssignment, stmt.class
      assert_equal i+1,           stmt.expr
    end
    assert_equal ASTAllOf, block.exprs[2].class
    assert_equal 'klass2', block.exprs[2].class_name
  end

  def test__either_optimize__preserves_return_value
    iff = ASTIf.new :condition => ASTCreateObjset.new, :then_expr => block, :else_expr => block
    iff = iff.optimize

    assert iff.is_a? ASTBlock
    assert_equal 2, iff.exprs.length
    assert          iff.exprs[0].is_a? ASTCreateObjset
    assert          iff.exprs[1].is_a? ASTEmptyObjset
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

  def test__action__declare_instance_vars
    action = ASTAction.new(:expr => block(
      iif(
        block(
          block(
            block(
              ASTAssignment.new(:expr => ASTVariableRead.new(:var_name => ASTIdent['kme']), :var_name => ASTIdent['at__kme'])
            ),
            block(
              ASTAssignment.new(:expr => ASTVariableRead.new(:var_name => ASTIdent['at__blahblah']), :var_name => ASTIdent['s'])
            ),
            block
          )
        ),
        block
      ),
      ASTDeleteObj.new
    ))

    action = action.optimize
    action.declare_instance_vars!

    assert_equal 3, action.expr.exprs.length


    assert_equal ASTAssignment,  action.expr.exprs[0].class
    assert_equal 'at__kme',      action.expr.exprs[0].var_name.text
    assert_equal ASTEmptyObjset, action.expr.exprs[0].expr.class
   
    assert_equal ASTIf, action.expr.exprs[1].class
    iff = action.expr.exprs[1]

    assert_equal ASTBlock,        iff.then_expr.class
    assert_equal 3,               iff.then_expr.exprs.length
    assert_equal ASTVariableRead, iff.then_expr.exprs[0].expr.class
    assert_equal 'kme',           iff.then_expr.exprs[0].expr.var_name.text
    assert_equal ASTVariableRead, iff.then_expr.exprs[1].expr.class
    assert_equal 'at__blahblah',  iff.then_expr.exprs[1].expr.var_name.text
    assert_false                  iff.then_expr.exprs[2].has_side_effects?
    assert_false                  iff.else_expr.has_side_effects?
    
    assert_equal ASTDeleteObj,   action.expr.exprs[2].class
  end

  def test__action__declare_instance_var_at_user
    action = ASTAction.new(:expr => block(
      iif(
        ASTAssignment.new(:expr => ASTCurrentUser.new, :var_name => ASTIdent["at__user"]),
        block
      ),
      ASTDeleteObj.new(:objset => ASTVariableRead.new(:var_name => ASTIdent["at__user"]))
    ))

    action = action.optimize
    action.declare_instance_vars!

    assert_equal 3, action.expr.exprs.length

    assert_equal ASTAssignment,  action.expr.exprs[0].class
    assert_equal 'at__user',     action.expr.exprs[0].var_name.text
    assert_equal ASTEmptyObjset, action.expr.exprs[0].expr.class
   
    assert_equal ASTIf,        action.expr.exprs[1].class
    assert_equal ASTDeleteObj, action.expr.exprs[2].class
  end

  def test__if_optimize__identical_paths
    iff = iif(ASTDeleteObj.new, ASTDeleteObj.new)
    opt = iff.optimize

    assert opt.is_a? ASTDeleteObj
  end

  def test__action_optimize__removes_last_stmts_without_sideeffects
    action = ASTAction.new(:expr => block(
      ASTCreateObjset.new,
      iif(ASTSubset.new, ASTAllOf.new)
    ))

    action.optimize!

    assert_equal ASTCreateObjset, action.expr.class
  end

  def test__adsl_ast_size
    ast = block(
      ASTAssignment.new(:var_name => ASTIdent['asd'], :expr => ASTEmptyObjset.new),
      dummy(:blah)
    )
    assert_equal 5, ast.adsl_ast_size

    ast = ASTBlock.new(:exprs => [])
    assert_equal 1, ast.adsl_ast_size
  end

  def test__spec_adsl_ast_size
    spec = ASTSpec.new(
      :classes => [ASTClass.new],
      :actions => [
        ASTAction.new(:name => ASTIdent.new(:text => 'action1')),
        ASTAction.new(:name => ASTIdent.new(:text => 'action2')),
        ASTAction.new(:name => ASTIdent.new(:text => '')),
      ],
      :invariants => [
        ASTInvariant.new(:name => ASTIdent.new(:text => 'inv_name1')),
        ASTInvariant.new(:name => ASTIdent.new(:text => 'inv_name2'))
      ]
    )

    assert_equal 12, spec.adsl_ast_size
    assert_equal 2, spec.adsl_ast_size(:action_name => 'action1')
    assert_equal 2, spec.adsl_ast_size(:action_name => 'action2')

    assert_equal 2, spec.adsl_ast_size(:invariant_name => 'inv_name1')
    
    assert_equal 4, spec.adsl_ast_size(:action_name => '', :invariant_name => 'inv_name2')
  end

  def test__spec_pre_optimize_size
    spec = ASTSpec.new(
      :classes => [ASTClass.new],
      :actions => [ASTAction.new(
        :name => ASTIdent['action'],
        :expr => block(
          dummy(:asd),
          iif(block, block)
        )
      )],
      :invariants => []
    )

    assert_equal 10, spec.adsl_ast_size
    assert_equal 8,  spec.actions.first.adsl_ast_size

    spec.optimize!

    assert_equal 8,  spec.actions.first.pre_optimize_adsl_ast_size
    assert_equal 3,  spec.actions.first.adsl_ast_size
    assert_equal 10, spec.pre_optimize_adsl_ast_size
    assert_equal 5,  spec.adsl_ast_size
  end

  def dummy(flag = nil)
    ASTFlag.new :label => flag
  end

  def return_stmt
    ASTReturn.new
  end

  def raise_stmt
    ASTRaise.new
  end

  def block(*stmts)
    ASTBlock.new :exprs => stmts
  end

  def iif(tthen, eelse)
    ASTIf.new :condition => ASTBoolean.new, :then_expr => tthen, :else_expr => eelse
  end

  def test_block_returns?
    assert block(dummy, dummy).halting_status.returns_never?
    assert block(dummy, return_stmt, dummy).halting_status.returns_always?
    assert block(iif(block, return_stmt)).halting_status.returns_sometimes?
  end

  def test_block__remove_statements_after_return
    b = block(dummy(1), return_stmt, dummy(2), dummy(3))
    
    b = b.remove_statements_after_returns
    
    assert_equal 2,         b.exprs.length
    assert_equal 1,         b.exprs[0].label
    assert_equal ASTReturn, b.exprs[1].class
  end

  def test_block_not_append_statements_after_return_to_returning_branches
    b = block(dummy(1), iif(return_stmt, block(return_stmt, dummy(2))), dummy(3))

    b = b.remove_statements_after_returns

    assert_equal 2,         b.exprs.length
    assert_equal 1,         b.exprs[0].label
    assert_equal ASTIf,     b.exprs[1].class
    assert_equal ASTReturn, b.exprs[1].then_expr.class
    assert_equal 1,         b.exprs[1].else_expr.exprs.length
    assert_equal ASTReturn, b.exprs[1].else_expr.exprs.first.class
  end

  def test_block_append_statements_after_return_to_nonreturning_branches
    b = block(dummy(1), iif(return_stmt, dummy(2)), dummy(3))
    
    b = b.remove_statements_after_returns

    assert_equal 2,         b.exprs.length
    assert_equal 1,         b.exprs[0].label
    assert_equal ASTIf,     b.exprs[1].class
    assert_equal ASTReturn, b.exprs[1].then_expr.class
    assert_equal ASTBlock,  b.exprs[1].else_expr.class
    assert_equal 2,         b.exprs[1].else_expr.exprs.length
    assert_equal [ASTFlag, ASTFlag], b.exprs[1].else_expr.exprs.map(&:class)
    assert_equal [2, 3],             b.exprs[1].else_expr.exprs.map(&:label)
  end

  def test_block__raise_after_return_does_not_raise
    b = block(dummy(1), return_stmt, raise_stmt)
    assert b.halting_status.raises_never?
    assert b.halting_status.returns_always?

    b = block(dummy(1), iif(return_stmt, dummy(1)), raise_stmt)
    assert b.halting_status.raises_sometimes?
    assert b.halting_status.returns_sometimes?
    
    b = block(dummy(1), iif(raise_stmt, dummy(1)), raise_stmt)
    assert b.halting_status.raises_always?
    assert b.halting_status.returns_never?

    b = block(dummy(1), iif(return_stmt, dummy(1)), return_stmt)
    assert b.halting_status.raises_never?
    assert b.halting_status.returns_always?
  end

end
