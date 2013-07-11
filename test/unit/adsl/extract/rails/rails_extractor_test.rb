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

  def test_adsl_ast__empty_action
    extractor = ADSL::Extract::Rails::RailsExtractor.new ar_classes
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    assert ast.block.statements.empty?
  end
  
  def test_adsl_ast__create_action
    AsdsController.class_exec do
      def create
        Asd.new
        respond_to
      end
    end
    
    extractor = ADSL::Extract::Rails::RailsExtractor.new ar_classes
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    assert_false ast.block.statements.empty?
    assert_equal ADSL::Parser::ASTCreateObj, ast.block.statements.first.class
    assert_equal 'Asd', ast.block.statements.first.class_name.text
  end

  def test_adsl_ast__create_within_expression_action
    AsdsController.class_exec do
      def create
        Asd.build
        respond_to
      end
    end
    
    extractor = ADSL::Extract::Rails::RailsExtractor.new ar_classes
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    assert_false ast.block.statements.empty?
    assert_equal ADSL::Parser::ASTCreateObj, ast.block.statements.first.class
    assert_equal 'Asd', ast.block.statements.first.class_name.text
  end

  def test_adsl_ast__variable_assignment
    AsdsController.class_exec do
      def create
        a = Asd.new
        a.save!
        respond_to
      end
    end
    
    extractor = ADSL::Extract::Rails::RailsExtractor.new ar_classes
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    assert_false ast.block.statements.empty?
    assert_equal ADSL::Parser::ASTAssignment, ast.block.statements.first.class
    assert_equal 'a', ast.block.statements.first.var_name.text
    assert_equal ADSL::Parser::ASTCreateObj, ast.block.statements.first.objset.class
    assert_equal 'Asd', ast.block.statements.first.objset.class_name.text
  end

end
