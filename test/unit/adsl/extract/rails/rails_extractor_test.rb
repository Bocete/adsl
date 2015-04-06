require 'minitest/unit'

require 'minitest/autorun'
require 'adsl/util/test_helper'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/rails/rails_extractor'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::Rails::RailsExtractorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
  include ::ADSL::Parser

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
    assert_raises ActionController::RoutingError do
      session.get('thisdoesntexist')
    end
  end

  def test_setup__rails_crashes_actually_crash_tests
    assert_raises ActionController::RoutingError do
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.get('no_route')
    end
  end

  def test_extract__empty_action
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    assert ast.block.statements.empty?
  end
  
  def test_extract__create_action
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
    assert_equal ASTExprStmt, statements.first.class
    assert_equal ASTCreateObjset, statements.first.expr.class
    assert_equal 'Asd', statements.first.expr.class_name.text
  end

  def test_extract__create_within_expression_action
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
    assert_equal ASTExprStmt, statements.first.class
    assert_equal ASTCreateObjset, statements.first.expr.class
    assert_equal 'Asd', statements.first.expr.class_name.text
  end

  def test_extract__variable_assignment
    AsdsController.class_exec do
      def create
        a = Asd.new
        a.delete!
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    statements = ast.block.statements

    assert_equal 2, statements.length
    assert_equal ASTExprStmt,   statements.first.class
    assert_equal ASTAssignment,   statements.first.expr.class
    assert_equal 'a',             statements.first.expr.var_name.text
    assert_equal ASTCreateObjset, statements.first.expr.expr.class
    assert_equal 'Asd',           statements.first.expr.expr.class_name.text
  end

  def test_extract__nil_assignment
    AsdsController.class_exec do
      def nothing
        a = nil
        a = Asd.new
        a.delete!
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 3, statements.length

    assert_equal ASTExprStmt,  statements[0].class
    assert_equal ASTAssignment,  statements[0].expr.class
    assert_equal 'a',            statements[0].expr.var_name.text
    assert_equal ASTEmptyObjset, statements[0].expr.expr.class

    assert_equal ASTExprStmt,   statements[1].class
    assert_equal ASTAssignment,   statements[1].expr.class
    assert_equal 'a',             statements[1].expr.var_name.text
    assert_equal ASTCreateObjset, statements[1].expr.expr.class
    assert_equal 'Asd',           statements[1].expr.expr.class_name.text
  end

  def test_extract__instance_variable_assignment
    AsdsController.class_exec do
      def create
        @a = Asd.new
        @a.save!
        a = nil
        @a.delete! # will throw an exception if a == @a
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    statements = ast.block.statements

    assert_equal 4, statements.length
    
    # all instance variables are initialized to empty
    assert_equal ASTExprStmt,    statements[0].class
    assert_equal ASTAssignment,  statements[0].expr.class
    assert_equal 'at__a',        statements[0].expr.var_name.text
    assert_equal ASTEmptyObjset, statements[0].expr.expr.class

    assert_equal ASTExprStmt,     statements[1].class
    assert_equal ASTAssignment,   statements[1].expr.class
    assert_equal 'at__a',         statements[1].expr.var_name.text
    assert_equal ASTCreateObjset, statements[1].expr.expr.class
    assert_equal 'Asd',           statements[1].expr.expr.class_name.text

    assert_equal ASTExprStmt,    statements[2].class
    assert_equal ASTAssignment,  statements[2].expr.class
    assert_equal 'a',            statements[2].expr.var_name.text
    assert_equal ASTEmptyObjset, statements[2].expr.expr.class
    
    assert_equal ASTDeleteObj, statements[3].class
    assert_equal 'at__a',      statements[3].objset.var_name.text
  end
  
  def test_extract__class_variable_assignment
    AsdsController.class_exec do
      def create
        @@a = Asd.new
        @@a.save!
        a = nil
        @a = nil
        @@a.delete! # will throw an exception if @@a == @a or @@ == a
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    statements = ast.block.statements

    assert_equal 5, statements.length
    
    assert_equal ASTExprStmt,     statements[0].class
    assert_equal ASTAssignment,   statements[0].expr.class
    assert_equal 'atat__a',       statements[0].expr.var_name.text
    assert_equal ASTEmptyObjset,  statements[0].expr.expr.class
    
    assert_equal ASTExprStmt,     statements[1].class
    assert_equal ASTAssignment,   statements[1].expr.class
    assert_equal 'atat__a',       statements[1].expr.var_name.text
    assert_equal ASTCreateObjset, statements[1].expr.expr.class
    assert_equal 'Asd',           statements[1].expr.expr.class_name.text

    assert_equal ASTExprStmt,     statements[2].class
    assert_equal ASTAssignment,   statements[2].expr.class
    assert_equal 'a',             statements[2].expr.var_name.text
    assert_equal ASTEmptyObjset,  statements[2].expr.expr.class
    
    assert_equal ASTExprStmt,     statements[3].class
    assert_equal ASTAssignment,   statements[3].expr.class
    assert_equal 'at__a',         statements[3].expr.var_name.text
    assert_equal ASTEmptyObjset,  statements[3].expr.expr.class
    
    assert_equal ASTDeleteObj, statements[4].class
    assert_equal ASTVariable,  statements[4].objset.class
    assert_equal 'atat__a',    statements[4].objset.var_name.text
  end

  def test_extract__assignments_dont_make_values_nil
    AsdsController.class_exec do
      def nothing
        a = Mod::Blah.new
        a.asd.delete
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length

    assert_equal ASTExprStmt,     statements[0].class
    assert_equal ASTAssignment,   statements[0].expr.class
    assert_equal ASTCreateObjset, statements[0].expr.expr.class
    assert_equal 'Mod_Blah',      statements[0].expr.expr.class_name.text
    assert_equal 'a',             statements[0].expr.var_name.text
    
    assert_equal ASTDeleteObj,    statements[1].class
    assert_equal ASTMemberAccess, statements[1].objset.class
    assert_equal 'asd',           statements[1].objset.member_name.text
    assert_equal ASTVariable,     statements[1].objset.objset.class
    assert_equal 'a',             statements[1].objset.objset.var_name.text
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

  def test_extract__nonreturning_branches
    AsdsController.class_exec do
      def nothing
        if :a
          Asd.new
        else
          Asd.find.delete!
        end
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ASTEither, statements.first.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 1, either.blocks.first.statements.length
    assert_equal ASTCreateObjset, either.blocks.first.statements.first.expr.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ASTDeleteObj, either.blocks.second.statements.first.class
  end

  def test_extract__one_returning_branch
    AsdsController.class_exec do
      def nothing
        if :not_a_deterministic_condition
          return Asd.new
        else
          Asd.build
        end
        Asd.find.delete!
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ASTEither, statements.first.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 1,               either.blocks.first.statements.length
    assert_equal ASTCreateObjset, either.blocks.first.statements.first.expr.class
    assert_equal 2,               either.blocks.second.statements.length
    assert_equal ASTCreateObjset, either.blocks.second.statements.first.expr.class
    assert_equal ASTDeleteObj,    either.blocks.second.statements.second.class
  end
  
  def test_extract__one_returning_branch_other_empty
    AsdsController.class_exec do
      def nothing
        if :not_a_deterministic_condition
          return Asd.new
        else
        end
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ASTExprStmt, statements.first.class
    assert_equal ASTCreateObjset, statements.first.expr.class
  end
  
  def test_extract__statements_after_return_are_ignored
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
    assert_equal ASTExprStmt, statements.first.class
    assert_equal ASTCreateObjset, statements.first.expr.class
  end

  def test_extract__statements_after_return_in_branches_are_ignored
    AsdsController.class_exec do
      def nothing
        if :not_a_deterministic_condition
          return Asd.new
        else
          return Asd.all
        end
        Asd.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length

    assert_equal ASTCreateObjset, statements[0].expr.class
    assert_equal 'Asd',           statements[0].expr.class_name.text
  end
  
  def test_extract__calls_of_method_with_multiple_paths
    AsdsController.class_exec do
      def something
        if :not_a_deterministic_condition
          return Asd.new
        else
          Asd.find.delete!
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
    assert_equal ASTEither, statements.first.class
    assert_equal ASTCreateObjset, statements.second.expr.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 1,               either.blocks.first.statements.length
    assert_equal ASTCreateObjset, either.blocks.first.statements.first.expr.class
    assert_equal 1,               either.blocks.second.statements.length
    assert_equal ASTDeleteObj,    either.blocks.second.statements.first.class
  end

  def test_extract__calls_of_method_with_compatible_return_values_but_sideeffects
    AsdsController.class_exec do
      def something
        if :not_a_deterministic_condition
          Asd.new
        else
          Asd.find
        end
      end

      def nothing
        something
        Kme.new
        render :text => 'asd'
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length

    assert_equal ASTEither,       statements.first.class
    assert_equal 1,               statements.first.blocks[0].statements.length
    assert_equal ASTCreateObjset, statements.first.blocks[0].statements.first.expr.class
    assert_equal 0,               statements.first.blocks[1].statements.length

    assert_equal ASTExprStmt,   statements.second.class
    assert_equal ASTCreateObjset, statements.second.expr.class
  end

  def test_extract__deep_call_chain
    AsdsController.class_exec do
      def some3
        Asd.new
        Asd.find
      end
      def some2; some3; end
      def some1; some2; end
      def nothing
        some1.destroy!
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    # 4 because of the destroy dependency
    assert_equal 4, statements.length

    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTCreateObjset, statements[0].expr.class
    assert_equal 'Asd',           statements[0].expr.class_name.text

    assert_equal ASTDeleteObj,    statements.last.class
    assert_equal ASTOneOf,        statements.last.objset.class
    assert_equal ASTAllOf,        statements.last.objset.objset.class
    assert_equal 'Asd',           statements.last.objset.objset.class_name.text
  end

  def test_extract__multiple_return
    AsdsController.class_exec do
      def blah
        return Asd.new, Kme.new
      end
      
      def nothing
        blah
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length

    assert_equal ASTCreateObjset, statements.first.expr.class
    assert_equal 'Asd', statements.first.expr.class_name.text
    
    assert_equal ASTCreateObjset, statements.second.expr.class
    assert_equal 'Kme', statements.second.expr.class_name.text
  end

  def test_extract__multiple_assignment
    AsdsController.class_exec do
      def nothing
        a, b = Asd.new, Kme.new
        a.delete!
        b.delete!
      end
    end
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 4, statements.length

    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTAssignment,   statements[0].expr.class
    assert_equal 'a',             statements[0].expr.var_name.text
    assert_equal ASTCreateObjset, statements[0].expr.expr.class
    assert_equal 'Asd',           statements[0].expr.expr.class_name.text
    
    assert_equal ASTExprStmt,   statements[1].class
    assert_equal ASTAssignment,   statements[1].expr.class
    assert_equal 'b',             statements[1].expr.var_name.text
    assert_equal ASTCreateObjset, statements[1].expr.expr.class
    assert_equal 'Kme',           statements[1].expr.expr.class_name.text
    
    assert_equal ASTDeleteObj, statements[2].class
    assert_equal 'a', statements[2].objset.var_name.text
    
    assert_equal ASTDeleteObj, statements[3].class
    assert_equal 'b', statements[3].objset.var_name.text
  end

  def test_extract__optional_assignment_of_known_nil_variable
    AsdsController.class_exec do
      def nothing
        a ||= Asd.new
        a = Asd.find
        a.delete!
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 4, statements.length

    assert_equal ASTDeclareVar,   statements[0].class
    assert_equal 'a',             statements[0].var_name.text
    assert_equal ASTEither,       statements[1].class
    assert_equal 2,               statements[1].blocks.length
    assert                        statements[1].blocks[0].statements.empty?
    assert_equal 1,               statements[1].blocks[1].statements.length
    assert_equal ASTExprStmt,   statements[1].blocks[1].statements[0].class
    assert_equal ASTAssignment,   statements[1].blocks[1].statements[0].expr.class
    assert_equal 'a',             statements[1].blocks[1].statements[0].expr.var_name.text
    assert_equal ASTCreateObjset, statements[1].blocks[1].statements[0].expr.expr.class
    assert_equal 'Asd',           statements[1].blocks[1].statements[0].expr.expr.class_name.text

    assert_equal ASTExprStmt, statements[2].class
    assert_equal ASTAssignment, statements[2].expr.class
    assert_equal 'a',           statements[2].expr.var_name.text
    assert_equal ASTOneOf,      statements[2].expr.expr.class
    assert_equal ASTAllOf,      statements[2].expr.expr.objset.class
    assert_equal 'Asd',         statements[2].expr.expr.objset.class_name.text
  end
  
  def test_extract__optional_assignment_of_nonnil_variable
    AsdsController.class_exec do
      def nothing
        a = Asd.new
        a ||= Asd.find
        a.delete!
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 4, statements.length

    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTAssignment,   statements[0].expr.class
    assert_equal 'a',             statements[0].expr.var_name.text
    assert_equal ASTCreateObjset, statements[0].expr.expr.class
    assert_equal 'Asd',           statements[0].expr.expr.class_name.text

    assert_equal ASTDeclareVar, statements[1].class
    assert_equal 'a',           statements[1].var_name.text
    assert_equal ASTEither,     statements[2].class
    assert_equal 2,             statements[2].blocks.length
    assert                      statements[2].blocks[0].statements.empty?
    assert_equal 1,             statements[2].blocks[1].statements.length
    assert_equal ASTExprStmt, statements[2].blocks[1].statements[0].class
    assert_equal ASTAssignment, statements[2].blocks[1].statements[0].expr.class
    assert_equal 'a',           statements[2].blocks[1].statements[0].expr.var_name.text
    assert_equal ASTOneOf,      statements[2].blocks[1].statements[0].expr.expr.class
    assert_equal ASTAllOf,      statements[2].blocks[1].statements[0].expr.expr.objset.class
    assert_equal 'Asd',         statements[2].blocks[1].statements[0].expr.expr.objset.class_name.text
  end
  
  def test_extract__multiple_assignment_of_return
    AsdsController.class_exec do
      def blah
        return Asd.new, Kme.new
      end
     
      def nothing
        a, b = blah
        a.delete!
        b.delete!
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 4, statements.length

    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTAssignment,   statements[0].expr.class
    assert_equal 'a',             statements[0].expr.var_name.text
    assert_equal ASTCreateObjset, statements[0].expr.expr.class
    assert_equal 'Asd',           statements[0].expr.expr.class_name.text
    
    assert_equal ASTExprStmt,   statements[1].class
    assert_equal ASTAssignment,   statements[1].expr.class
    assert_equal 'b',             statements[1].expr.var_name.text
    assert_equal ASTCreateObjset, statements[1].expr.expr.class
    assert_equal 'Kme',           statements[1].expr.expr.class_name.text
    
    assert_equal ASTDeleteObj, statements[2].class
    assert_equal 'a', statements[2].objset.var_name.text
    
    assert_equal ASTDeleteObj, statements[3].class
    assert_equal 'b', statements[3].objset.var_name.text
  end
  
  def test_extract__variable_assignment_in_branch
    AsdsController.class_exec do
      def nothing
        if :not_a_deterministic_condition
          a = "asd"
        else
          a = "blah"
        end
        return a
      end
    end
    
    assert_nothing_raised do
      extractor = create_rails_extractor
      ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    end
  end

  def test_callback_lookup
    extractor = create_rails_extractor
    assert_set_equal(
      [:before, :after, :before2, :before_nothing, :after_nothing, :authorize!],
      extractor.callbacks(AsdsController).map(&:filter)
    )
  end

  def test_before_callbacks__instrumented
    AsdsController.class_exec do
      def before
        Asd.new
      end

      def before_filter_action
        Kme.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :before_filter_action)
    statements = ast.block.statements

    assert_equal 2, statements.length
    assert_equal 'Asd', statements[0].expr.class_name.text
    assert_equal 'Kme', statements[1].expr.class_name.text
  end
  
  def test_after_callbacks__instrumented
    AsdsController.class_exec do
      def after_filter_action
        Kme.new
      end

      def after
        Asd.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :after_filter_action)
    statements = ast.block.statements

    assert_equal 2, statements.length
    assert_equal 'Kme', statements[0].expr.class_name.text
    assert_equal 'Asd', statements[1].expr.class_name.text
  end
  
  def test_before_callbacks__can_have_branches_normally
    AsdsController.class_exec do
      def before
        if :not_a_deterministic_condition
          return Kme.new
        else
          Asd.new
        end
      end
      
      def before2
        if :not_a_deterministic_condition
          Kme.new
        else
        end
      end

      def before_filter_action
        Mod::Blah.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :before_filter_action)
    statements = ast.block.statements

    assert_equal 3, statements.length

    assert_equal ASTEither, statements[0].class
    assert_equal 2, statements[0].blocks.length
    blocks = statements[0].blocks
    assert_equal 1,             blocks[0].statements.length
    assert_equal ASTExprStmt, blocks[0].statements[0].class
    assert_equal 'Kme',         blocks[0].statements[0].expr.class_name.text
    assert_equal 1,             blocks[1].statements.length
    assert_equal ASTExprStmt, blocks[1].statements[0].class
    assert_equal 'Asd',         blocks[1].statements[0].expr.class_name.text
    
    assert_equal ASTEither, statements[1].class
    assert_equal 2, statements[1].blocks.length
    blocks = statements[1].blocks
    assert_equal 1,             blocks[0].statements.length
    assert_equal ASTExprStmt, blocks[0].statements[0].class
    assert_equal 'Kme',         blocks[0].statements[0].expr.class_name.text
    assert_equal 0,             blocks[1].statements.length

    assert_equal ASTExprStmt, statements[2].class
    assert_equal 'Mod_Blah',    statements[2].expr.class_name.text
  end
  
  def test_after_callbacks__can_have_branches_normally
    AsdsController.class_exec do
      def after_filter_action
        Mod::Blah.new
      end
      
      def after
        if :not_a_deterministic_condition
          Kme.new
        else
          return Asd.new
        end
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :after_filter_action)
    statements = ast.block.statements

    assert_equal 2, statements.length
    
    assert_equal ASTExprStmt, statements[0].class
    assert_equal 'Mod_Blah',    statements[0].expr.class_name.text

    assert_equal ASTEither, statements[1].class
    assert_equal 2,         statements[1].blocks.length
    blocks = statements[1].blocks
    assert_equal 1,             blocks[0].statements.length
    assert_equal ASTExprStmt, blocks[0].statements[0].class
    assert_equal 'Kme',         blocks[0].statements[0].expr.class_name.text
    assert_equal 1,             blocks[1].statements.length
    assert_equal ASTExprStmt, blocks[1].statements[0].class
    assert_equal 'Asd',         blocks[1].statements[0].expr.class_name.text
  end

  def test_callbacks__multiple_branched_callbacks
    AsdsController.class_exec do
      def before_nothing
        if :not_a_deterministic_condition
          return Kme.new
        else
          Asd.new
        end
      end

      def nothing
        if :not_a_deterministic_condition
          Kme.new
        else
          return Mod::Blah.new
        end
      end

      def after_nothing
        if :not_a_deterministic_condition
          return Kme.new
        else
          Mod::Blah.new
        end
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 3, statements.length

    expected_classnames = ['Asd', 'Mod_Blah', 'Mod_Blah']
    3.times do |index|
      assert_equal ASTEither, statements[index].class
      blocks =                statements[index].blocks
      assert_equal 2,         blocks.length
      assert_equal 1,                          blocks[0].statements.length
      assert_equal ASTExprStmt,              blocks[0].statements[0].class
      assert_equal 'Kme',                      blocks[0].statements[0].expr.class_name.text
      assert_equal 1,                          blocks[1].statements.length
      assert_equal ASTExprStmt,              blocks[1].statements[0].class
      assert_equal expected_classnames[index], blocks[1].statements[0].expr.class_name.text
    end
  end

  def test_before_callbacks__halt_callback_chain_when_rendering_always
    AsdsController.class_exec do
      def before
        render :text => 'blah'
      end

      def before2
        Mod::Blah.new
      end
      
      def before_filter_action
        Mod::Blah.new
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :before_filter_action)
    statements = ast.block.statements

    assert_equal 1,        statements.length
    assert_equal ASTRaise, statements[0].class
  end
  
  def test_before_callbacks__halt_callback_chain_when_rendering_sometimes
    AsdsController.class_exec do
      def before
        if :not_a_deterministic_condition
          render :text => 'blah'
        end
        Asd.new
      end

      def before2
        Kme.new
      end
      
      def before_filter_action
        Mod::Blah.new
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :before_filter_action)
    statements = ast.block.statements

    assert_equal 3, statements.length
    assert_equal 3, statements.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal ASTExprStmt, statements[i].class
      assert_equal types[i],    statements[i].expr.class_name.text
    end
  end

  def test_before_callbacks__affect_after
    AsdsController.class_exec do
      def before_nothing
        if :not_a_deterministic_condition
          render
        end
        Asd.new
      end
      
      def nothing
        Kme.new
      end

      def after_nothing
        Mod::Blah.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 3, statements.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal ASTExprStmt, statements[i].class
      assert_equal types[i],    statements[i].expr.class_name.text
    end
  end

  def test_before_callbacks__render_in_action_does_not_halt_after
    AsdsController.class_exec do
      def before_nothing
        if :not_a_deterministic_condition
          render
        end
        Asd.new
      end
      
      def nothing
        Kme.new
        render :text => 'blah'
      end

      def after_nothing
        Mod::Blah.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 3, statements.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal ASTExprStmt,      statements[i].class
      assert_equal types[i],         statements[i].expr.class_name.text
    end
  end

  def test_extract__instrumentation_filters_work
    AsdsController.class_exec do
      def before_nothing
        Asd.new
      end

      def nothing
        Asd.new
      end
    end
    
    extractor = create_rails_extractor <<-filters
      blacklist :before_nothing
    filters

    assert_equal 1, extractor.instrumentation_filters.length

    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements
    assert_equal 1, statements.length
  end
  
  def test_extract__raise_ignores_the_root_path
    AsdsController.class_exec do
      def nothing
        Kme.new
        raise
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1,        statements.length
    assert_equal ASTRaise, statements.first.class
  end

  def test_extract__raise_ignores_the_root_path_in_branch
    AsdsController.class_exec do
      def nothing
        if :not_a_deterministic_condition
          Asd.new
        else
          Kme.new
          raise
        end
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTCreateObjset, statements[0].expr.class
    assert_equal 'Asd',           statements[0].expr.class_name.text
  end
  
  def test_extract__exceptions_in_callbacks_stop_the_chain
    AsdsController.class_exec do
      def before_nothing
        raise
      end

      def nothing
        Asd.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1,        statements.length
    assert_equal ASTRaise, statements[0].class
  end

  def test_extract__foreach_basic
    AsdsController.class_exec do
      def nothing
        Kme.all.each do |asd|
          a = asd
          a.delete!
        end
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length

    foreach = statements.first
    assert_equal ASTForEach, foreach.class
    assert_equal 'asd',      foreach.var_name.text
    assert_equal ASTAllOf,   foreach.objset.class
    assert_equal 'Kme',      foreach.objset.class_name.text
    assert_equal ASTBlock,   foreach.block.class

    block_stmts = foreach.block.statements
    assert_equal 2,             block_stmts.length
    assert_equal ASTExprStmt, block_stmts[0].class
    assert_equal ASTAssignment, block_stmts[0].expr.class
    assert_equal ASTVariable,   block_stmts[0].expr.expr.class
    assert_equal 'asd',         block_stmts[0].expr.expr.var_name.text
    assert_equal 'a',           block_stmts[0].expr.var_name.text
    assert_equal ASTDeleteObj,  block_stmts[1].class
    assert_equal 'a',           block_stmts[1].objset.var_name.text
  end

  def test_extract__association_setter_direct
    AsdsController.class_exec do
      def nothing
        Kme.new.blah = Mod::Blah.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements
    
    assert_equal 1, statements.length

    assert_equal ASTMemberSet,    statements[0].class
    assert_equal ASTCreateObjset, statements[0].objset.class
    assert_equal 'Kme',           statements[0].objset.class_name.text
    assert_equal 'blah',          statements[0].member_name.text
    assert_equal ASTMemberSet,    statements[0].class
    assert_equal ASTCreateObjset, statements[0].expr.class
    assert_equal 'Mod_Blah',      statements[0].expr.class_name.text
  end

  def test_extract__association_setter_through
    AsdsController.class_exec do
      def nothing
        Asd.find.kmes = Kme.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements
    
    assert_equal 4, statements.length

    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTAssignment, statements[0].expr.class
    origin_name =               statements[0].expr.var_name.text
    assert_equal ASTOneOf,      statements[0].expr.expr.class
    assert_equal ASTAllOf,      statements[0].expr.expr.objset.class
    assert_equal 'Asd',         statements[0].expr.expr.objset.class_name.text
    
    assert_equal ASTExprStmt,     statements[1].class
    assert_equal ASTAssignment,   statements[1].expr.class
    target_name =                 statements[1].expr.var_name.text
    assert_equal ASTCreateObjset, statements[1].expr.expr.class
    assert_equal 'Kme',           statements[1].expr.expr.class_name.text

    assert_equal ASTDeleteObj,    statements[2].class
    assert_equal ASTMemberAccess, statements[2].objset.class
    assert_equal ASTVariable,     statements[2].objset.objset.class
    assert_equal origin_name,     statements[2].objset.objset.var_name.text
    assert_equal 'blahs',         statements[2].objset.member_name.text
 
    assert_equal ASTForEach,  statements[3].class
    iter_name =               statements[3].var_name.text
    assert_equal ASTVariable, statements[3].objset.class
    assert_equal target_name, statements[3].objset.var_name.text
    block =                   statements[3].block

    assert_equal 3, block.statements.length

    assert_equal ASTExprStmt,   block.statements[0].class
    assert_equal ASTAssignment,   block.statements[0].expr.class
    temp_name =                   block.statements[0].expr.var_name.text
    assert_equal ASTCreateObjset, block.statements[0].expr.expr.class
    assert_equal 'Mod_Blah',      block.statements[0].expr.expr.class_name.text

    assert_equal ASTCreateTup, block.statements[1].class
    assert_equal ASTVariable,  block.statements[1].objset1.class
    assert_equal origin_name,  block.statements[1].objset1.var_name.text
    assert_equal 'blahs',      block.statements[1].rel_name.text
    assert_equal ASTVariable,  block.statements[1].objset2.class
    assert_equal temp_name,    block.statements[1].objset2.var_name.text

    assert_equal ASTCreateTup, block.statements[2].class
    assert_equal ASTVariable,  block.statements[2].objset1.class
    assert_equal temp_name,    block.statements[2].objset1.var_name.text
    assert_equal 'kme12',      block.statements[2].rel_name.text
    assert_equal ASTVariable,  block.statements[2].objset2.class
    assert_equal iter_name,    block.statements[2].objset2.var_name.text

    assert_equal 4, [origin_name, target_name, temp_name, iter_name].uniq.length
    assert origin_name.is_a? String
    assert target_name.is_a? String
    assert temp_name.is_a? String
    assert iter_name.is_a? String
  end

  def test_extract__nested_foreachs
    AsdsController.class_exec do
      def nothing
        Asd.all.each do |asd|
          asd.blahs.each do |blah|
            blah.delete
          end
        end
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements
    
    assert_equal 1, statements.length

    assert_equal ASTForEach, statements.first.class
    assert_equal ASTAllOf,   statements.first.objset.class
    assert_equal 'Asd',      statements.first.objset.class_name.text
    assert_equal 'asd',      statements.first.var_name.text

    block_stmts = statements.first.block.statements

    assert_equal 1,               block_stmts.length
    assert_equal ASTForEach,      block_stmts.first.class
    assert_equal ASTMemberAccess, block_stmts.first.objset.class
    assert_equal ASTVariable,     block_stmts.first.objset.objset.class
    assert_equal 'asd',           block_stmts.first.objset.objset.var_name.text
    assert_equal 'blahs',         block_stmts.first.objset.member_name.text
    assert_equal 'blah',          block_stmts.first.var_name.text

    final_block_stmts = block_stmts.first.block.statements

    assert_equal 1,            final_block_stmts.length
    assert_equal ASTDeleteObj, final_block_stmts.first.class
    assert_equal ASTVariable,  final_block_stmts.first.objset.class
    assert_equal 'blah',       final_block_stmts.first.objset.var_name.text
  end

  def test_extract__assignment_in_branch_condition
    AsdsController.class_exec do
      def nothing
        if asd = Asd.new
          asd.delete
        end
        asd.delete
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 3, statements.length

    assert_equal ASTExprStmt,     statements[0].class
    assert_equal ASTAssignment,   statements[0].expr.class
    assert_equal 'asd',           statements[0].expr.var_name.text
    assert_equal ASTCreateObjset, statements[0].expr.expr.class
    assert_equal 'Asd',           statements[0].expr.expr.class_name.text

    assert_equal ASTIf,       statements[1].class
    assert_equal ASTVariable, statements[1].condition.class
    assert_equal 1,           statements[1].then_block.statements.length
    assert_equal ASTDeleteObj,statements[1].then_block.statements[0].class
    assert_equal ASTVariable, statements[1].then_block.statements[0].objset.class
    assert_equal 'asd',       statements[1].then_block.statements[0].objset.var_name.text
    assert_equal 0,           statements[1].else_block.statements.length

    assert_equal ASTDeleteObj, statements[2].class
    assert_equal ASTVariable,  statements[2].objset.class
    assert_equal 'asd',        statements[2].objset.var_name.text
  end

  def test_extract__assignment_of_branch
    AsdsController.class_exec do
      def nothing
        a = if Asd.all.empty?; Asd.all; else; nil; end
        a.delete
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 3, statements.length

    assert_equal ASTIf,      statements[0].class
    assert_equal ASTIsEmpty, statements[0].condition.class
    assert_equal [],         statements[0].then_block.statements
    assert_equal [],         statements[0].else_block.statements

    assert_equal ASTExprStmt,    statements[1].class
    assert_equal ASTAssignment,  statements[1].expr.class
    assert_equal 'a',            statements[1].expr.var_name.text
    assert_equal ASTIfExpr,      statements[1].expr.expr.class
    assert_equal statements[0],  statements[1].expr.expr.if
    assert_equal ASTAllOf,       statements[1].expr.expr.then_expr.class
    assert_equal ASTEmptyObjset, statements[1].expr.expr.else_expr.class

    assert_equal ASTDeleteObj, statements[2].class
    assert_equal ASTVariable,  statements[2].objset.class
    assert_equal 'a',          statements[2].objset.var_name.text
  end

  def test_extract__assignment_of_unconditional_branch
    AsdsController.class_exec do
      def nothing
        a = if :unconditional; Asd.all; else; nil; end
        a.delete
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length

    assert_equal ASTExprStmt,      statements[0].class
    assert_equal ASTAssignment,    statements[0].expr.class
    assert_equal 'a',              statements[0].expr.var_name.text
    assert_equal ASTPickOneExpr,   statements[0].expr.expr.class
    assert_equal ASTAllOf,         statements[0].expr.expr.exprs[0].class
    assert_equal ASTEmptyObjset,   statements[0].expr.expr.exprs[1].class

    assert_equal ASTDeleteObj, statements[1].class
    assert_equal ASTVariable,  statements[1].objset.class
    assert_equal 'a',          statements[1].objset.var_name.text
  end
  
  def test_extract__assignment_of_trinary
    AsdsController.class_exec do
      def nothing
        a = Asd.all.empty? ? Asd.all : nil
        a.delete
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 3, statements.length

    assert_equal ASTIf,            statements[0].class
    assert_equal ASTIsEmpty,       statements[0].condition.class
    assert_equal [],               statements[0].then_block.statements
    assert_equal [],               statements[0].else_block.statements

    assert_equal ASTExprStmt,      statements[1].class
    assert_equal ASTAssignment,    statements[1].expr.class
    assert_equal 'a',              statements[1].expr.var_name.text
    assert_equal ASTIfExpr,        statements[1].expr.expr.class
    assert_equal ASTAllOf,         statements[1].expr.expr.then_expr.class
    assert_equal ASTEmptyObjset,   statements[1].expr.expr.else_expr.class

    assert_equal ASTDeleteObj, statements[2].class
    assert_equal ASTVariable,  statements[2].objset.class
    assert_equal 'a',          statements[2].objset.var_name.text
  end
  
  def test_extract__rescue_stmt_modifier
    AsdsController.class_exec do
      def nothing
        a = Asd.all rescue nil
        a.delete
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length

    assert_equal ASTExprStmt,      statements[0].class
    assert_equal ASTAssignment,    statements[0].expr.class
    assert_equal 'a',              statements[0].expr.var_name.text
    assert_equal ASTPickOneExpr,   statements[0].expr.expr.class
    assert_equal ASTEmptyObjset,   statements[0].expr.expr.exprs[0].class
    assert_equal ASTAllOf,         statements[0].expr.expr.exprs[1].class

    assert_equal ASTDeleteObj, statements[1].class
    assert_equal ASTVariable,  statements[1].objset.class
    assert_equal 'a',          statements[1].objset.var_name.text
  end

  def test_extract__action_may_call_action
    AsdsController.class_exec do
      def nothing
        Asd.new
      end

      def create
        Kme.new
        nothing
        Mod::Blah.new
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    statements = ast.block.statements

    assert_equal 3, statements.length

    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTCreateObjset, statements[0].expr.class
    assert_equal 'Kme',           statements[0].expr.class_name.text
    assert_equal ASTExprStmt,   statements[1].class
    assert_equal ASTCreateObjset, statements[1].expr.class
    assert_equal 'Asd',           statements[1].expr.class_name.text
    assert_equal ASTExprStmt,   statements[2].class
    assert_equal ASTCreateObjset, statements[2].expr.class
    assert_equal 'Mod_Blah',      statements[2].expr.class_name.text
  end

  def test_extract__foreign_key_reads_and_writes_propagate_kinda
    AsdsController.class_exec do
      def nothing
        blah = Mod::Blah.find
        asd = Asd.find

        blah.asd_id = asd.id
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 3, statements.length

    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTAssignment, statements[0].expr.class
    assert_equal 'blah',        statements[0].expr.var_name.text
    assert_equal ASTOneOf,      statements[0].expr.expr.class
    assert_equal ASTAllOf,      statements[0].expr.expr.objset.class
    assert_equal 'Mod_Blah',    statements[0].expr.expr.objset.class_name.text

    assert_equal ASTExprStmt,   statements[1].class
    assert_equal ASTAssignment, statements[1].expr.class
    assert_equal 'asd',         statements[1].expr.var_name.text
    assert_equal ASTOneOf,      statements[1].expr.expr.class
    assert_equal ASTAllOf,      statements[1].expr.expr.objset.class
    assert_equal 'Asd',         statements[1].expr.expr.objset.class_name.text

    assert_equal ASTMemberSet,  statements[2].class
    assert_equal ASTVariable,   statements[2].objset.class
    assert_equal 'blah',        statements[2].objset.var_name.text
    assert_equal 'asd',         statements[2].member_name.text
    assert_equal ASTVariable,   statements[2].expr.class
    assert_equal 'asd',         statements[2].expr.var_name.text
  end

  def test_extract__has_many_delete_removes_one
    AsdsController.class_exec do
      def nothing
        a = Asd.new
        a.blahs.delete(1)
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length

    assert_equal ASTExprStmt,   statements[0].class
    assert_equal ASTAssignment,   statements[0].expr.class
    assert_equal 'a',             statements[0].expr.var_name.text
    assert_equal ASTCreateObjset, statements[0].expr.expr.class
    assert_equal 'Asd',           statements[0].expr.expr.class_name.text

    assert_equal ASTDeleteTup,    statements[1].class
    assert_equal ASTVariable,     statements[1].objset1.class
    assert_equal 'a',             statements[1].objset1.var_name.text
    assert_equal 'blahs',         statements[1].rel_name.text
    assert_equal ASTOneOf,        statements[1].objset2.class
    assert_equal ASTMemberAccess, statements[1].objset2.objset.class
    assert_equal 'blahs',         statements[1].objset2.objset.member_name.text
    assert_equal ASTVariable,     statements[1].objset2.objset.objset.class
    assert_equal 'a',             statements[1].objset2.objset.objset.var_name.text
  end
end
