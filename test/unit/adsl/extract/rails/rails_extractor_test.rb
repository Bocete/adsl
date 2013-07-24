require 'test/unit'
require 'adsl/util/test_helper'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/rails/rails_extractor'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::Rails::RailsExtractorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase

  def test_setup__routes
    route_set = ADSLRailsTestApplication.routes.routes
    
    assert route_set.map{ |route| route.ast.to_s }.include? '/asds/nothing(.:format)'
  end

  def test_setup__active_record
    assert_false self.class.lookup_const(:Asd).nil?
    assert_false self.class.lookup_const(:Kme).nil?
    assert_false self.class.lookup_const('Mod::Blah').nil?
  end

  def test_setup__urls_visible
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.get('/asds/nothing')
    assert_equal 200, session.response.status
    assert session.response.body.strip.empty?

    session = ActionDispatch::Integration::Session.new(Rails.application)
    assert_raise ActionController::RoutingError do
      session.get('thisdoesntexist')
    end
  end

  def test_setup__rails_crashes_actually_crash_tests
    assert_raise do
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.get('no_route')
    end
  end

  def test_action_extraction__empty_action
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    assert ast.block.statements.empty?
  end
  
  def test_action_extraction__create_action
    AsdsController.class_exec do
      def create
        Asd.new
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create) 
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ADSL::Parser::ASTObjsetStmt, statements.first.class
    assert_equal ADSL::Parser::ASTCreateObjset, statements.first.objset.class
    assert_equal 'Asd', statements.first.objset.class_name.text
  end

  def test_action_extraction__create_within_expression_action
    AsdsController.class_exec do
      def create
        Asd.build
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create) 
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ADSL::Parser::ASTObjsetStmt, statements.first.class
    assert_equal ADSL::Parser::ASTCreateObjset, statements.first.objset.class
    assert_equal 'Asd', statements.first.objset.class_name.text
  end

  def test_action_extraction__variable_assignment
    AsdsController.class_exec do
      def create
        a = Asd.new
        a.save!
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    statements = ast.block.statements

    assert_false statements.empty?
    assert_equal 1, statements.length
    assert_equal ADSL::Parser::ASTAssignment, statements.first.class
    assert_equal 'a', statements.first.var_name.text
    assert_equal ADSL::Parser::ASTCreateObjset, statements.first.objset.class
    assert_equal 'Asd', statements.first.objset.class_name.text
  end

  def test_invariant_extraction__works
    extractor = create_rails_extractor <<-invariants
      invariant 'what', true
    invariants

    invariants = extractor.invariants
    assert_equal 1, invariants.length
    assert_equal 'what', invariants.first.name.text
    assert_equal true, invariants.first.formula.bool_value
  end

  def test_action_extraction__nonreturning_branches
    AsdsController.class_exec do
      def nothing
        if something
          Asd.new
        else
          Asd.find.destroy!
        end
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ADSL::Parser::ASTEither, statements.first.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 1, either.blocks.first.statements.length
    assert_equal ADSL::Parser::ASTCreateObjset, either.blocks.first.statements.first.objset.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ADSL::Parser::ASTDeleteObj, either.blocks.second.statements.first.class
  end

  def test_action_extraction__one_returning_branch
    AsdsController.class_exec do
      def nothing
        if something
          return Asd.new
        else
          Asd.build
        end
        Asd.find.destroy!
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ADSL::Parser::ASTEither, statements.first.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 2, either.blocks.first.statements.length
    assert_equal ADSL::Parser::ASTCreateObjset, either.blocks.first.statements.first.objset.class
    assert_equal ADSL::Parser::ASTDeleteObj, either.blocks.first.statements.second.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ADSL::Parser::ASTCreateObjset, either.blocks.second.statements.first.objset.class
  end
  
  def test_action_extraction__one_returning_branch_other_empty
    AsdsController.class_exec do
      def nothing
        if something
          return Asd.new
        else
        end
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ADSL::Parser::ASTObjsetStmt, statements.first.class
    assert_equal ADSL::Parser::ASTCreateObjset, statements.first.objset.class
  end
  
  def test_action_extraction__statements_after_return_are_ignored
    AsdsController.class_exec do
      def nothing
        Asd.new
        return
        Asd.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ADSL::Parser::ASTObjsetStmt, statements.first.class
    assert_equal ADSL::Parser::ASTCreateObjset, statements.first.objset.class
  end

  def test_action_extraction__statements_after_return_in_branches_are_ignored
    AsdsController.class_exec do
      def nothing
        if anything
          return Asd.new
        else
          return Asd.new
        end
        Asd.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ADSL::Parser::ASTEither, statements.first.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 1, either.blocks.first.statements.length
    assert_equal ADSL::Parser::ASTCreateObjset, either.blocks.first.statements.first.objset.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ADSL::Parser::ASTCreateObjset, either.blocks.second.statements.first.objset.class
  end
  
  def test_action_extraction__calls_of_method_with_multiple_paths
    AsdsController.class_exec do
      def something
        if whatever
          return Asd.new
        else
          Asd.find.destroy!
        end
      end

      def nothing
        something
        return Asd.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length
    assert_equal ADSL::Parser::ASTEither, statements.first.class
    assert_equal ADSL::Parser::ASTCreateObjset, statements.second.objset.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 1, either.blocks.first.statements.length
    assert_equal ADSL::Parser::ASTDeleteObj, either.blocks.first.statements.first.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ADSL::Parser::ASTCreateObjset, either.blocks.second.statements.first.objset.class
  end
  
end
