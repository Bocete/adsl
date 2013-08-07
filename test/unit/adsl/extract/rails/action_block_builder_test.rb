require 'adsl/extract/rails/action_block_builder'
require 'adsl/extract/rails/other_meta'
require 'adsl/parser/ast_nodes'

module ADSL::Extract::Rails
  class ActionBlockBuilderTest < Test::Unit::TestCase
    include ADSL::Parser

    def test__in_stmt_frame
      abb = ActionBlockBuilder.new
      
      assert_equal([:a, :b, :d], abb.in_stmt_frame do
        abb << :a
        abb << :b
        assert_equal([:c], abb.in_stmt_frame do
          abb << :c
        end)
        abb << :d
      end)
      
      assert_equal([:a, :b, :d], abb.in_stmt_frame do
        abb << :a
        abb << :b
        assert_equal([:c], abb.in_stmt_frame do
          abb << :c
        end)
        abb << :d
      end)
    end

    def test__all_stmts_so_far
      abb = ActionBlockBuilder.new
      
      abb.in_stmt_frame do
        abb << :a
        abb << :b
        abb.in_stmt_frame do
          abb << :c
          assert_equal [:a, :b, :c], abb.all_stmts_so_far
        end
        abb << :d
        assert_equal [:a, :b, :d], abb.all_stmts_so_far
      end
      assert abb.all_stmts_so_far.empty?
      
      abb.in_stmt_frame do
        abb << :a
        abb << :b
        abb.in_stmt_frame do
          abb << :c
          assert_equal [:a, :b, :c], abb.all_stmts_so_far
        end
        abb << :d
        assert_equal [:a, :b, :d], abb.all_stmts_so_far
      end
      assert abb.all_stmts_so_far.empty?
    end

    def test__branch_choice__no_branches
      abb = ActionBlockBuilder.new
      abb.explore_all_choices do
        abb << :a
      end
      assert_equal [[:a]], abb.root_paths
    end

    def test__branch_choice
      abb = ActionBlockBuilder.new

      abb.explore_all_choices do
        abb << :a
        abb << :b
        if abb.branch_choice 1
          abb << :c
          if abb.branch_choice 2
            abb << :d
            abb.do_return :nil
            abb << :e
          else
            abb << :f
          end
        else
          abb << :g
          abb.do_return :nil
          abb << :h
        end
        abb << :i
        if abb.branch_choice 3
          abb << :j
        else
          abb << :k
        end
        abb << :l
      end

      expected_choices = [
        [:a, :b, :c, :d],
        [:a, :b, :c, :f, :i, :j, :l],
        [:a, :b, :c, :f, :i, :k, :l],
        [:a, :b, :g]
      ]

      assert_set_equal expected_choices, abb.root_paths
    end

    def test__common_return_value
      abb = ActionBlockBuilder.new
      
      assert_equal(:a, abb.explore_all_choices do
        abb.do_return :a
      end)
      
      ret_value = abb.explore_all_choices do
        if abb.branch_choice 1
          abb.do_return :a
        else
          abb.do_return :b
        end
      end

      assert_equal ::ADSL::Extract::Rails::MetaUnknown, ret_value.class
    end

    def test__common_return_value__ignores_duplicates
      abb = ActionBlockBuilder.new
      
      assert_equal(:a, abb.explore_all_choices do
        if abb.branch_choice 1
          abb.do_return :a
        else
          abb.do_return :a
        end
      end)
    end

    def test__common_return_value__implicit
      abb = ActionBlockBuilder.new
      
      assert_equal(:c, abb.explore_all_choices do
        abb << :b
        abb << :c
      end)

      ret_value = abb.explore_all_choices do
        abb << :c
        if abb.branch_choice 1
          abb << :a
        else
          abb << :c
        end
      end

      assert_equal ::ADSL::Extract::Rails::MetaUnknown, ret_value.class
    end

    def test__common_return_value__looks_at_do_return_at_not_the_actual_return_value
      abb = ActionBlockBuilder.new
      
      assert_equal(:a, abb.explore_all_choices do
        abb.do_return :a
        abb << :b
      end)
    end

    def test__adsl_ast__simple
      abb = ActionBlockBuilder.new
      abb.explore_all_choices do
        abb << :a
        abb << :b
        abb << :c
      end
      adsl_ast = abb.adsl_ast
      assert_equal ASTBlock, adsl_ast.class
      assert_equal [:a, :b, :c], adsl_ast.statements
    end

  end
end
