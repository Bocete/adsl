require 'test/unit'
require 'adsl/util/test_helper'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/rails/callback_chain_simulator'

module ADSL::Extract::Rails
  class CallbackChainSimulatorTest < Test::Unit::TestCase
    include ADSL::Parser
    include ADSL::Extract::Rails::CallbackChainSimulator

    def dummy(flag = nil)
      ASTDummyStmt.new :type => flag
    end

    def render
      ASTDummyStmt.new :type => :render
    end

    def block(*stmts)
      ASTBlock.new :statements => stmts
    end

    def either(*blocks)
      ASTEither.new :blocks => blocks
    end

    def test_render_status_of__plain_blocks
      assert_equal false, render_status_of(block dummy, dummy)
      assert_equal true,  render_status_of(block dummy, render, dummy)
    end

    def test_render_status_of__plain_either
      assert_equal nil, render_status_of(either(
        block,
        block(render)
      ))

      assert_equal true, render_status_of(either(
        block(render),
        block(render)
      ))
      
      assert_equal false, render_status_of(either(block, block))
    end

    def test_split_paths__plain
      paths = split_into_paths_that_must_or_may_not_render(block(
        dummy(0),
        either(
          block(dummy 1),
          block(dummy 2),
          block(dummy(3), render)
        ),
        dummy(4)
      ))
   
      # rendering:     0, 3, 4
      stmts = paths[:render].statements
      assert_equal 3, stmts.length
      assert_equal 0, stmts[0].type
      assert_equal [3, :render], stmts[1].statements.map(&:type)
      assert_equal 4, stmts[2].type

      # non-rendering: 0, 1, 4 or 0, 2, 4
      stmts = paths[:not_render].statements
      assert_equal 3,   stmts.length
      
      assert_equal 0,         stmts[0].type
      assert_equal ASTEither, stmts[1].class
      assert_equal 2,         stmts[1].blocks.length
      assert_equal [1, 2],    stmts[1].blocks.map(&:statements).map(&:first).map(&:type)
      assert_equal 4,         stmts[2].type
    end

  end
end
