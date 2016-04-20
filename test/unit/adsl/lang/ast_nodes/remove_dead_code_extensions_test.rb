require 'adsl/util/test_helper'
require 'adsl/lang/ast_nodes'
require 'adsl/lang/ast_nodes/remove_dead_code_extensions'
require 'set'

module ADSL::Lang
  module ASTNodes
    class ASTNodes::RemoveReadCodeExtensionsTest < ActiveSupport::TestCase
   
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
  end
end
