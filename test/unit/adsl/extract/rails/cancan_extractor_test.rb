require 'minitest/unit'

require 'minitest/autorun'
require 'adsl/util/test_helper'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/rails/cancan_extractor'
require 'adsl/extract/rails/rails_extractor'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::Rails::CanCanExtractorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
  include ::ADSL::Parser

  def setup
    super
    define_cancan_suite
    Ability.class_exec do
      def initialize(user)
        if user.is_admin
          can :manage, :all
        else
          can :read, Asd, :user_id => user.id
          can :menage, User, :id => user.id
        end
      end
    end
  end

  def teardown
    unload_class :CanCan, :User, :Ability
  end

  def test_setup_and_teardown
    extractor = create_rails_extractor
    ast = extractor.adsl_ast

    assert_equal 4, ast.classes.length
    
    userNode = ast.classes.select{ |c| c.name.text == 'User' }.first
    assert userNode
    assert userNode.authenticable

    assert_equal 2, ast.usergroups.length
    assert_set_equal %w|admin nonadmin|, ast.usergroups.map(&:name).map(&:text)
  end

  def test_policy_set
    extractor = create_rails_extractor
    ast = extractor.adsl_ast

    permits = ast.ac_rules
  end

  def test_currentuser_in_action
    AsdsController.class_exec do
      def create
        @user = current_user
        respond_to
      end
    end
   
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create) 
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ASTExprStmt,    statements.first.class
    assert_equal ASTAssignment,  statements.first.expr.class
    assert_equal 'at__user',     statements.first.expr.var_name.text
    assert_equal ASTCurrentUser, statements.first.expr.expr.class
  end

  def test_can_test_in_action
    AsdsController.class_exec do
      def create
        raise unless can? :create, User
        @user = User.new
        respond_to
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create) 
    statements = ast.block.statements

    assert_equal 1,                  statements.length
    assert_equal ASTIf,              statements.first.class
    assert_equal ASTPermittedByType, statements.first.condition.class
    assert_equal [:create],          statements.first.condition.ops
    assert_equal 'User',             statements.first.condition.class_name.text
    assert_equal [],                 statements.first.else_block.statements
    assert_equal 1,                  statements.first.then_block.statements.length
    assert_equal ASTExprStmt,        statements.first.then_block.statements[0].class
    assert_equal ASTAssignment,      statements.first.then_block.statements[0].expr.class
    assert_equal 'at__user',         statements.first.then_block.statements[0].expr.var_name.text
    assert_equal ASTCreateObjset,    statements.first.then_block.statements[0].expr.expr.class
    assert_equal 'User',             statements.first.then_block.statements[0].expr.expr.class_name.text
  end

  def test_can_manage_all_extracted
    extractor = create_rails_extractor
    ast = extractor.adsl_ast
    expected = ASTPermit.new(
      :expr => ASTAllOf.new(:class_name => ASTIdent.new(:text => 'Mod_Blah')),
      :ops => [:edit, :read],
      :group_names => [ASTIdent.new(:text => 'admin')]
    )

    assert ast.ac_rules.include?(expected)
  end

end
