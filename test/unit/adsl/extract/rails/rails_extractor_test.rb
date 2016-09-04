require 'adsl/util/test_helper'
require 'adsl/lang/ast_nodes'
require 'adsl/extract/rails/rails_extractor'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::Rails::RailsExtractorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
  include ::ADSL::Lang

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

  def test_setup__asds_have_a_string_field
    assert Asd.columns_hash.keys.include? 'field'
    assert Asd.columns_hash['field'].type == :string
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
    assert_equal ASTEmptyObjset, ast.expr.class
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

    assert_equal ASTCreateObjset, ast.expr.class
    assert_equal 'Asd',           ast.expr.class_name.text
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

    exprs = ast.expr.exprs

    assert_equal 2, exprs.length
    assert_equal ASTAssignment,   exprs.first.class
    assert_equal 'a',             exprs.first.var_name.text
    assert_equal ASTCreateObjset, exprs.first.expr.class
    assert_equal 'Asd',           exprs.first.expr.class_name.text
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
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length

    assert_equal ASTAssignment,  exprs[0].class
    assert_equal 'a',            exprs[0].var_name.text
    assert_equal ASTEmptyObjset, exprs[0].expr.class

    assert_equal ASTAssignment,   exprs[1].class
    assert_equal 'a',             exprs[1].var_name.text
    assert_equal ASTCreateObjset, exprs[1].expr.class
    assert_equal 'Asd',           exprs[1].expr.class_name.text
  end

  def test_extract__instance_variable_assignment
    AsdsController.class_exec do
      def create
        @a = Asd.new
        @a.save!
        a = Asd.new
        @a.delete! # will throw an exception if a == @a
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length

    assert_equal ASTAssignment,   exprs[0].class
    assert_equal 'at__a',         exprs[0].var_name.text
    assert_equal ASTCreateObjset, exprs[0].expr.class
    assert_equal 'Asd',           exprs[0].expr.class_name.text

    assert_equal ASTCreateObjset, exprs[1].class
    assert_equal 'Asd',           exprs[1].class_name.text
  
    assert_equal ASTDeleteObj, exprs[2].class
    assert_equal 'at__a',      exprs[2].objset.var_name.text
  end

  def test_extract__class_variable_assignment
    AsdsController.class_exec do
      def create
        @@a = Asd.new
        @@a.save!
        a = Asd.new
        @a = nil
        @@a.delete! # will throw an exception if @@a == @a or @@ == a
        respond_to
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    exprs = ast.expr.exprs

    assert_equal 4, exprs.length
    
    assert_equal ASTAssignment,   exprs[0].class
    assert_equal 'atat__a',       exprs[0].var_name.text
    assert_equal ASTCreateObjset, exprs[0].expr.class
    assert_equal 'Asd',           exprs[0].expr.class_name.text

    assert_equal ASTCreateObjset, exprs[1].class
    assert_equal 'Asd',           exprs[1].class_name.text
    
    assert_equal ASTAssignment,  exprs[2].class
    assert_equal 'at__a',        exprs[2].var_name.text
    assert_equal ASTEmptyObjset, exprs[2].expr.class
    
    assert_equal ASTDeleteObj,    exprs[3].class
    assert_equal ASTVariableRead, exprs[3].objset.class
    assert_equal 'atat__a',        exprs[3].objset.var_name.text
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
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTAssignment,   exprs[0].class
    assert_equal ASTCreateObjset, exprs[0].expr.class
    assert_equal 'Mod_Blah',      exprs[0].expr.class_name.text
    assert_equal 'a',             exprs[0].var_name.text
    
    assert_equal ASTDeleteObj,    exprs[1].class
    assert_equal ASTMemberAccess, exprs[1].objset.class
    assert_equal 'asd',           exprs[1].objset.member_name.text
    assert_equal ASTVariableRead, exprs[1].objset.objset.class
    assert_equal 'a',             exprs[1].objset.objset.var_name.text
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

    assert_equal ASTIf, ast.expr.class

    iff = ast.expr

    assert_equal ASTCreateObjset, iff.then_expr.class
    assert_equal 'Asd',           iff.then_expr.class_name.text
    assert_equal ASTDeleteObj,    iff.else_expr.class
    assert_equal ASTOneOf,        iff.else_expr.objset.class
    assert_equal ASTAllOf,        iff.else_expr.objset.objset.class
    assert_equal 'Asd',           iff.else_expr.objset.objset.class_name.text
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

    assert_equal ASTIf, ast.expr.class
    iff = ast.expr

    assert_equal ASTBoolean,      iff.condition.class
    assert_equal nil,             iff.condition.bool_value

    assert_equal ASTCreateObjset, iff.then_expr.class
    assert_equal 'Asd',           iff.then_expr.class_name.text

    assert_equal ASTBlock,        iff.else_expr.class
    assert_equal 2,               iff.else_expr.exprs.length
    assert_equal ASTCreateObjset, iff.else_expr.exprs.first.class
    assert_equal ASTDeleteObj,    iff.else_expr.exprs.second.class
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

    assert_equal ASTIf, ast.expr.class
    iff = ast.expr

    assert_equal ASTBoolean,      iff.condition.class
    assert_equal nil,             iff.condition.bool_value

    assert_equal ASTCreateObjset, iff.then_expr.class
    assert_equal 'Asd',           iff.then_expr.class_name.text

    assert iff.else_expr.noop?
  end
  
  def test_extract__exprs_after_return_are_ignored
    AsdsController.class_exec do
      def nothing
        Asd.new
        return
        Asd.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    assert_equal ASTCreateObjset, ast.expr.class
  end

  def test_extract__exprs_after_return_in_branches_are_ignored
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

    assert_equal ASTIf, ast.expr.class
    iff = ast.expr

    assert_equal ASTBoolean,      iff.condition.class
    assert_equal nil,             iff.condition.bool_value

    assert_equal ASTCreateObjset, iff.then_expr.class
    assert_equal 'Asd',           iff.then_expr.class_name.text

    assert_equal ASTAllOf,        iff.else_expr.class
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

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs
    assert_equal 2,        exprs.length

    assert_equal ASTIf,           exprs[0].class
    iff = exprs.first
    assert_equal ASTBoolean,      iff.condition.class
    assert_equal nil,             iff.condition.bool_value
    assert_equal ASTCreateObjset, iff.then_expr.class
    assert_equal 'Asd',           iff.then_expr.class_name.text
    assert_equal ASTDeleteObj,    iff.else_expr.class
    assert_equal ASTOneOf,        iff.else_expr.objset.class
    assert_equal ASTAllOf,        iff.else_expr.objset.objset.class
    assert_equal 'Asd',           iff.else_expr.objset.objset.class_name.text

    assert_equal ASTCreateObjset, exprs[1].class
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

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs
    assert_equal 2,        exprs.length

    assert_equal ASTIf,           exprs[0].class
    iff = exprs.first
    assert_equal ASTBoolean,      iff.condition.class
    assert_equal nil,             iff.condition.bool_value
    assert_equal ASTCreateObjset, iff.then_expr.class
    assert_equal 'Asd',           iff.then_expr.class_name.text
    assert_equal ASTOneOf,        iff.else_expr.class
    assert_equal ASTAllOf,        iff.else_expr.objset.class
    assert_equal 'Asd',           iff.else_expr.objset.class_name.text

    assert_equal ASTCreateObjset, exprs[1].class
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
        @a = some1
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    assert_equal ASTAssignment, ast.expr.class
    assert_equal 'at__a',       ast.expr.var_name.text
    assert_equal ASTBlock,      ast.expr.expr.class
    block = ast.expr.expr
    assert_equal 2,               block.exprs.length
    assert_equal ASTCreateObjset, block.exprs.first.class
    assert_equal ASTOneOf,        block.exprs.second.class
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
    exprs = ast.expr.exprs

    assert_equal 4, exprs.length

    assert_equal ASTAssignment,   exprs[0].class
    assert_equal 'a',             exprs[0].var_name.text
    assert_equal ASTCreateObjset, exprs[0].expr.class
    assert_equal 'Asd',           exprs[0].expr.class_name.text
    
    assert_equal ASTAssignment,   exprs[1].class
    assert_equal 'b',             exprs[1].var_name.text
    assert_equal ASTCreateObjset, exprs[1].expr.class
    assert_equal 'Kme',           exprs[1].expr.class_name.text
    
    assert_equal ASTDeleteObj, exprs[2].class
    assert_equal 'a', exprs[2].objset.var_name.text
    
    assert_equal ASTDeleteObj, exprs[3].class
    assert_equal 'b', exprs[3].objset.var_name.text
  end

  def test_extract__optional_assignment_of_known_nil_variable
    AsdsController.class_exec do
      def nothing
        @a ||= Asd.find
        @a = Asd.where
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTAssignment,   exprs[0].class
    assert_equal 'at__a',         exprs[0].var_name.text
    assert_equal ASTIf,           exprs[0].expr.class
    assert_equal ASTIsEmpty,      exprs[0].expr.condition.class
    assert_equal ASTVariableRead, exprs[0].expr.condition.objset.class
    assert_equal 'at__a',         exprs[0].expr.condition.objset.var_name.text
    assert_equal ASTOneOf,        exprs[0].expr.then_expr.class
    assert_equal ASTAllOf,        exprs[0].expr.then_expr.objset.class
    assert_equal 'Asd',           exprs[0].expr.then_expr.objset.class_name.text
    assert_equal ASTVariableRead, exprs[0].expr.else_expr.class
    assert_equal 'at__a',         exprs[0].expr.else_expr.var_name.text
    
    assert_equal ASTAssignment, exprs[1].class
    assert_equal 'at__a',       exprs[1].var_name.text
    assert_equal ASTSubset,     exprs[1].expr.class
    assert_equal ASTAllOf,      exprs[1].expr.objset.class
    assert_equal 'Asd',         exprs[1].expr.objset.class_name.text
  end
  
  def test_extract__optional_assignment_of_nonnil_variable
    AsdsController.class_exec do
      def nothing
        @a = Asd.where
        @a ||= Asd.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length
    
    assert_equal ASTAssignment, exprs[0].class
    assert_equal 'at__a',       exprs[0].var_name.text
    assert_equal ASTSubset,     exprs[0].expr.class
    assert_equal ASTAllOf,      exprs[0].expr.objset.class
    assert_equal 'Asd',         exprs[0].expr.objset.class_name.text

    assert_equal ASTAssignment,   exprs[1].class
    assert_equal 'at__a',         exprs[1].var_name.text
    assert_equal ASTIf,           exprs[1].expr.class
    assert_equal ASTIsEmpty,      exprs[1].expr.condition.class
    assert_equal ASTVariableRead, exprs[1].expr.condition.objset.class
    assert_equal 'at__a',         exprs[1].expr.condition.objset.var_name.text
    assert_equal ASTCreateObjset, exprs[1].expr.then_expr.class
    assert_equal 'Asd',           exprs[1].expr.then_expr.class_name.text
    assert_equal ASTVariableRead, exprs[1].expr.else_expr.class
    assert_equal 'at__a',         exprs[1].expr.else_expr.var_name.text
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
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
  end

  def test_callback_lookup
    extractor = create_rails_extractor
    actual_callbacks = Set[*extractor.callbacks(AsdsController).map(&:filter)]
    expected_callbacks = Set[:before, :after, :before2, :before_nothing, :after_nothing]

    assert actual_callbacks >= expected_callbacks
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
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length
    assert_equal 'Asd', exprs[0].class_name.text
    assert_equal 'Kme', exprs[1].class_name.text
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
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length
    assert_equal 'Kme', exprs[0].class_name.text
    assert_equal 'Asd', exprs[1].class_name.text
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

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length

    assert_equal ASTIf,           exprs[0].class
    assert_equal ASTBoolean,      exprs[0].condition.class
    assert_equal nil,             exprs[0].condition.bool_value
    assert_equal ASTCreateObjset, exprs[0].then_expr.class
    assert_equal 'Kme',           exprs[0].then_expr.class_name.text
    assert_equal ASTCreateObjset, exprs[0].else_expr.class
    assert_equal 'Asd',           exprs[0].else_expr.class_name.text
    
    assert_equal ASTIf,           exprs[1].class
    assert_equal ASTBoolean,      exprs[1].condition.class
    assert_equal nil,             exprs[1].condition.bool_value
    assert_equal ASTCreateObjset, exprs[1].then_expr.class
    assert_equal 'Kme',           exprs[1].then_expr.class_name.text
    assert                        exprs[1].else_expr.noop?

    assert_equal ASTCreateObjset, exprs[2].class
    assert_equal 'Mod_Blah',      exprs[2].class_name.text 
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
    
    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length
    
    assert_equal ASTCreateObjset, exprs[0].class
    assert_equal 'Mod_Blah',      exprs[0].class_name.text
    
    assert_equal ASTIf,           exprs[1].class
    assert_equal ASTBoolean,      exprs[1].condition.class
    assert_equal nil,             exprs[1].condition.bool_value
    assert_equal ASTCreateObjset, exprs[1].then_expr.class
    assert_equal 'Kme',           exprs[1].then_expr.class_name.text
    assert_equal ASTCreateObjset, exprs[1].else_expr.class
    assert_equal 'Asd',           exprs[1].else_expr.class_name.text
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
    
    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length

    expected_classnames = ['Asd', 'Mod_Blah', 'Mod_Blah']
    expected_classnames.each_index do |expected, index|
      assert_equal ASTIf,      exprs[index].class
      assert_equal ASTBoolean, exprs[index].condition.class
      assert_equal nil,        exprs[index].condition.bool_value

      assert_equal ASTCreateObjset, exprs[index].then_expr.class
      assert_equal 'Kme',           exprs[index].then_expr.class_name.text
      assert_equal ASTCreateObjset, exprs[index].else_expr.class
      assert_equal expected,        exprs[index].else_expr.class_name.text
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
    assert_equal ASTRaise, ast.expr.class
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
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length
    assert_equal 3, exprs.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal types[i],    exprs[i].class_name.text
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
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal types[i],    exprs[i].class_name.text
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
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal types[i],         exprs[i].class_name.text
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
    assert_equal ASTCreateObjset, ast.expr.class # as opposed to a block
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

    assert_equal ASTRaise, ast.expr.class
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

    assert_equal ASTCreateObjset, ast.expr.class
    assert_equal 'Asd',           ast.expr.class_name.text
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

    assert_equal ASTRaise, ast.expr.class
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

    foreach = ast.expr
    assert_equal ASTForEach, foreach.class
    assert_equal 'asd',      foreach.var_name.text
    assert_equal ASTAllOf,   foreach.objset.class
    assert_equal 'Kme',      foreach.objset.class_name.text

    assert_equal ASTBlock,   foreach.expr.class
    block_stmts = foreach.expr.exprs
    assert_equal 2,               block_stmts.length
    assert_equal ASTAssignment,   block_stmts[0].class
    assert_equal ASTVariableRead, block_stmts[0].expr.class
    assert_equal 'asd',           block_stmts[0].expr.var_name.text
    assert_equal 'a',             block_stmts[0].var_name.text
    assert_equal ASTDeleteObj,    block_stmts[1].class
    assert_equal 'a',             block_stmts[1].objset.var_name.text
  end

  def test_extract__association_setter_direct
    AsdsController.class_exec do
      def nothing
        Kme.new.blah = Mod::Blah.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    
    assert_equal ASTMemberSet,    ast.expr.class
    assert_equal ASTCreateObjset, ast.expr.objset.class
    assert_equal 'Kme',           ast.expr.objset.class_name.text
    assert_equal 'blah',          ast.expr.member_name.text
    assert_equal ASTMemberSet,    ast.expr.class
    assert_equal ASTCreateObjset, ast.expr.expr.class
    assert_equal 'Mod_Blah',      ast.expr.expr.class_name.text
  end

  def test_extract__association_setter_through
    AsdsController.class_exec do
      def nothing
        Asd.find.kmes = Kme.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    exprs = ast.expr.exprs
    
    assert_equal 4, exprs.length

    assert_equal ASTAssignment, exprs[0].class
    origin_name =               exprs[0].var_name.text
    assert_equal ASTOneOf,      exprs[0].expr.class
    assert_equal ASTAllOf,      exprs[0].expr.objset.class
    assert_equal 'Asd',         exprs[0].expr.objset.class_name.text
    
    assert_equal ASTAssignment,   exprs[1].class
    target_name =                 exprs[1].var_name.text
    assert_equal ASTCreateObjset, exprs[1].expr.class
    assert_equal 'Kme',           exprs[1].expr.class_name.text

    assert_equal ASTDeleteObj,    exprs[2].class
    assert_equal ASTMemberAccess, exprs[2].objset.class
    assert_equal ASTVariableRead,     exprs[2].objset.objset.class
    assert_equal origin_name,     exprs[2].objset.objset.var_name.text
    assert_equal 'blahs',         exprs[2].objset.member_name.text
 
    assert_equal ASTForEach,  exprs[3].class
    iter_name =               exprs[3].var_name.text
    assert_equal ASTVariableRead, exprs[3].objset.class
    assert_equal target_name, exprs[3].objset.var_name.text
    block =                   exprs[3].expr

    assert_equal 3, block.exprs.length

    assert_equal ASTAssignment,   block.exprs[0].class
    temp_name =                   block.exprs[0].var_name.text
    assert_equal ASTCreateObjset, block.exprs[0].expr.class
    assert_equal 'Mod_Blah',      block.exprs[0].expr.class_name.text

    assert_equal ASTCreateTup, block.exprs[1].class
    assert_equal ASTVariableRead,  block.exprs[1].objset1.class
    assert_equal origin_name,  block.exprs[1].objset1.var_name.text
    assert_equal 'blahs',      block.exprs[1].rel_name.text
    assert_equal ASTVariableRead,  block.exprs[1].objset2.class
    assert_equal temp_name,    block.exprs[1].objset2.var_name.text

    assert_equal ASTCreateTup, block.exprs[2].class
    assert_equal ASTVariableRead,  block.exprs[2].objset1.class
    assert_equal temp_name,    block.exprs[2].objset1.var_name.text
    assert_equal 'kme12',      block.exprs[2].rel_name.text
    assert_equal ASTVariableRead,  block.exprs[2].objset2.class
    assert_equal iter_name,    block.exprs[2].objset2.var_name.text

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
    
    assert_equal ASTForEach, ast.expr.class
    assert_equal ASTAllOf,   ast.expr.objset.class
    assert_equal 'Asd',      ast.expr.objset.class_name.text
    assert_equal 'asd',      ast.expr.var_name.text

    outside_loop_body = ast.expr.expr

    assert_equal ASTForEach,      outside_loop_body.class
    assert_equal ASTMemberAccess, outside_loop_body.objset.class
    assert_equal ASTVariableRead, outside_loop_body.objset.objset.class
    assert_equal 'asd',           outside_loop_body.objset.objset.var_name.text
    assert_equal 'blahs',         outside_loop_body.objset.member_name.text
    assert_equal 'blah',          outside_loop_body.var_name.text

    inside_loop_body = outside_loop_body.expr

    assert_equal ASTDeleteObj,    inside_loop_body.class
    assert_equal ASTVariableRead, inside_loop_body.objset.class
    assert_equal 'blah',          inside_loop_body.objset.var_name.text
  end

  def test_extract__assignment_in_branch_condition
    AsdsController.class_exec do
      def nothing
        if asd = Asd.where
          asd.delete
        end
        asd.delete
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTIf,         exprs[0].class
    assert_equal ASTNot,        exprs[0].condition.class
    assert_equal ASTIsEmpty,    exprs[0].condition.subformula.class
    assert_equal ASTAssignment, exprs[0].condition.subformula.objset.class
    assert_equal 'asd',         exprs[0].condition.subformula.objset.var_name.text
    assert_equal ASTSubset,     exprs[0].condition.subformula.objset.expr.class
    assert_equal ASTDeleteObj,  exprs[0].then_expr.class
    assert                      exprs[0].else_expr.noop?

    assert_equal ASTDeleteObj,    exprs[1].class
    assert_equal ASTVariableRead, exprs[1].objset.class
    assert_equal 'asd',           exprs[1].objset.var_name.text
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

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTAssignment,  exprs[0].class
    assert_equal 'a',            exprs[0].var_name.text
    assert_equal ASTIf,          exprs[0].expr.class
    assert_equal ASTIsEmpty,     exprs[0].expr.condition.class
    assert_equal ASTAllOf,       exprs[0].expr.then_expr.class
    assert_equal ASTEmptyObjset, exprs[0].expr.else_expr.class

    assert_equal ASTDeleteObj,    exprs[1].class
    assert_equal ASTVariableRead, exprs[1].objset.class
    assert_equal 'a',             exprs[1].objset.var_name.text
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

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTAssignment,  exprs[0].class
    assert_equal 'a',            exprs[0].var_name.text
    assert_equal ASTIf,          exprs[0].expr.class
    assert_equal ASTBoolean,     exprs[0].expr.condition.class
    assert_equal nil,            exprs[0].expr.condition.bool_value
    assert_equal ASTAllOf,       exprs[0].expr.then_expr.class
    assert_equal ASTEmptyObjset, exprs[0].expr.else_expr.class

    assert_equal ASTDeleteObj,    exprs[1].class
    assert_equal ASTVariableRead, exprs[1].objset.class
    assert_equal 'a',             exprs[1].objset.var_name.text
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

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTAssignment,  exprs[0].class
    assert_equal 'a',            exprs[0].var_name.text
    assert_equal ASTIf,          exprs[0].expr.class
    assert_equal ASTIsEmpty,     exprs[0].expr.condition.class
    assert_equal ASTAllOf,       exprs[0].expr.then_expr.class
    assert_equal ASTEmptyObjset, exprs[0].expr.else_expr.class

    assert_equal ASTDeleteObj,    exprs[1].class
    assert_equal ASTVariableRead, exprs[1].objset.class
    assert_equal 'a',             exprs[1].objset.var_name.text
  end
  
  def test_extract__assignment_of_incompatible_type_branch
    AsdsController.class_exec do
      def nothing
        @a = Asd.all.empty? ? Asd.all : Kme.all
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    assert_equal ASTAssignment, ast.expr.class
    assert_equal 'at__a',       ast.expr.var_name.text
    assert_equal ASTIf,         ast.expr.expr.class
    assert_equal ASTIsEmpty,    ast.expr.expr.condition.class
    assert_equal ASTAllOf,      ast.expr.expr.then_expr.class
    assert_equal 'Asd',         ast.expr.expr.then_expr.class_name.text
    assert_equal ASTAllOf,      ast.expr.expr.else_expr.class
    assert_equal 'Kme',         ast.expr.expr.else_expr.class_name.text
  end

  def test_extract__try_call
    AsdsController.class_exec do
      def nothing
        @a = Asd.where
        @a.try :destroy!
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    assert_equal ASTBlock, ast.expr.class
    assert_equal 2,        ast.expr.exprs.length

    assignment = ast.expr.exprs.first
    assert_equal ASTAssignment, assignment.class
    assert_equal 'at__a',       assignment.var_name.text
    assert_equal ASTSubset,     assignment.expr.class

    try = ast.expr.exprs.second
    assert_equal ASTIf,           try.class
    assert_equal ASTNot,          try.condition.class
    assert_equal ASTIsEmpty,      try.condition.subformula.class
    assert_equal ASTAssignment,   try.condition.subformula.objset.class
    var_name = try.condition.subformula.objset.var_name
    assert_equal ASTVariableRead, try.condition.subformula.objset.expr.class
    assert_equal 'at__a',         try.condition.subformula.objset.expr.var_name.text
    assert_equal ASTBlock,        try.then_expr.class
    try.then_expr.exprs.each do |stmt|
      assert_equal ASTDeleteObj, stmt.class
      expr = stmt.objset
      expr = expr.objset while expr.is_a? ASTMemberAccess
      assert_equal ASTVariableRead, expr.class
      assert_equal var_name,        expr.var_name
    end
    assert_equal ASTEmptyObjset,  try.else_expr.class
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
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTAssignment,  exprs[0].class
    assert_equal 'a',            exprs[0].var_name.text
    assert_equal ASTIf,          exprs[0].expr.class
    assert_equal ASTBoolean,     exprs[0].expr.condition.class
    assert_equal nil,            exprs[0].expr.condition.bool_value
    assert_equal ASTAllOf,       exprs[0].expr.then_expr.class
    assert_equal ASTEmptyObjset, exprs[0].expr.else_expr.class

    assert_equal ASTDeleteObj,    exprs[1].class
    assert_equal ASTVariableRead, exprs[1].objset.class
    assert_equal 'a',             exprs[1].objset.var_name.text
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
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length

    assert_equal ASTCreateObjset, exprs[0].class
    assert_equal 'Kme',           exprs[0].class_name.text
    assert_equal ASTCreateObjset, exprs[1].class
    assert_equal 'Asd',           exprs[1].class_name.text
    assert_equal ASTCreateObjset, exprs[2].class
    assert_equal 'Mod_Blah',      exprs[2].class_name.text
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
    exprs = ast.expr.exprs

    assert_equal 3, exprs.length

    assert_equal ASTAssignment, exprs[0].class
    assert_equal 'blah',        exprs[0].var_name.text
    assert_equal ASTOneOf,      exprs[0].expr.class
    assert_equal ASTAllOf,      exprs[0].expr.objset.class
    assert_equal 'Mod_Blah',    exprs[0].expr.objset.class_name.text

    assert_equal ASTAssignment, exprs[1].class
    assert_equal 'asd',         exprs[1].var_name.text
    assert_equal ASTOneOf,      exprs[1].expr.class
    assert_equal ASTAllOf,      exprs[1].expr.objset.class
    assert_equal 'Asd',         exprs[1].expr.objset.class_name.text

    assert_equal ASTMemberSet,  exprs[2].class
    assert_equal ASTVariableRead,   exprs[2].objset.class
    assert_equal 'blah',        exprs[2].objset.var_name.text
    assert_equal 'asd',         exprs[2].member_name.text
    assert_equal ASTVariableRead,   exprs[2].expr.class
    assert_equal 'asd',         exprs[2].expr.var_name.text
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
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTAssignment,   exprs[0].class
    assert_equal 'a',             exprs[0].var_name.text
    assert_equal ASTCreateObjset, exprs[0].expr.class
    assert_equal 'Asd',           exprs[0].expr.class_name.text

    assert_equal ASTDeleteTup,    exprs[1].class
    assert_equal ASTVariableRead, exprs[1].objset1.class
    assert_equal 'a',             exprs[1].objset1.var_name.text
    assert_equal 'blahs',         exprs[1].rel_name.text
    assert_equal ASTOneOf,        exprs[1].objset2.class
    assert_equal ASTMemberAccess, exprs[1].objset2.objset.class
    assert_equal 'blahs',         exprs[1].objset2.objset.member_name.text
    assert_equal ASTVariableRead, exprs[1].objset2.objset.objset.class
    assert_equal 'a',             exprs[1].objset2.objset.objset.var_name.text
  end

  def test_extract__field_comparison_resolves_to_unknown_branch_condition
    AsdsController.class_exec do
      def nothing
        a = Asd.new
        if a.field == "something"
          a.destroy
        end
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 2, exprs.length

    assert_equal ASTAssignment,   exprs[0].class
    assert_equal 'a',             exprs[0].var_name.text
    assert_equal ASTCreateObjset, exprs[0].expr.class
    assert_equal 'Asd',           exprs[0].expr.class_name.text

    assert_equal ASTIf,        exprs[1].class
    assert_equal ASTBoolean,   exprs[1].condition.class
    assert_equal nil,          exprs[1].condition.bool_value
  end

  def test_extract__find_by
    AsdsController.class_exec do
      def nothing
        a = Asd.find_by_name 'name'
        a.destroy
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    assert_equal ASTBlock, ast.expr.class
    exprs = ast.expr.exprs

    assert_equal 4, exprs.length

    assert_equal ASTAssignment, exprs[0].class
    assert_equal 'a',           exprs[0].var_name.text
    assert_equal ASTOneOf,      exprs[0].expr.class
    assert_equal ASTAllOf,      exprs[0].expr.objset.class
    assert_equal 'Asd',         exprs[0].expr.objset.class_name.text

    assert_equal ASTDeleteObj, exprs[1].class
    assert_equal ASTDeleteObj, exprs[2].class
    assert_equal ASTDeleteObj, exprs[3].class
  end

  def test_extract__method_raises_by_default
    AsdsController.class_exec do
      def asd
        a = Asd.where
        return a if a
        raise
      end
      
      def nothing
        asd.destroy!
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    block = ast.expr.exprs
    assert_equal 4, block.length

    assert_equal ASTAssignment,    block[0].class
    assert_equal 3,                block[0].expr.exprs.length
    assert_equal ASTAssignment,    block[0].expr.exprs[0].class
    assert_equal ASTAssertFormula, block[0].expr.exprs[1].class
    assert_equal ASTVariableRead,  block[0].expr.exprs[2].class

    block[1..-1].each do |expr|
      assert_equal ASTDeleteObj, expr.class
    end
  end

  def test_extract__multiple_optional_returns_get_flat
    AsdsController.class_exec do
      def nothing
        if Asd.where
          return
        else
          @kme = Kme.find
        end
        return if Asd.where
        raise
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    assert_equal ASTBlock,         ast.expr.class

    assert_equal ASTAssignment,    ast.expr.exprs[0].class
    assert_equal 'at__kme',        ast.expr.exprs[0].var_name.text

    assert_equal ASTIf,            ast.expr.exprs[1].class
    assert_equal ASTIsEmpty,       ast.expr.exprs[1].condition.class
    assert_equal ASTSubset,        ast.expr.exprs[1].condition.objset.class
    assert_equal ASTEmptyObjset,   ast.expr.exprs[1].else_expr.class
    assert_equal ASTBlock,         ast.expr.exprs[1].then_expr.class
    assert_equal 3,                ast.expr.exprs[1].then_expr.exprs.length
    assert_equal ASTAssignment,    ast.expr.exprs[1].then_expr.exprs[0].class
    assert_equal 'at__kme',        ast.expr.exprs[1].then_expr.exprs[0].var_name.text
    assert_equal ASTAssertFormula, ast.expr.exprs[1].then_expr.exprs[1].class
    assert_equal ASTEmptyObjset,   ast.expr.exprs[1].then_expr.exprs[2].class
  end

  def test_extract__block_pass
    Asd.class_exec do
      def custom_destroy
        destroy!
        nil
      end
    end
    AsdsController.class_exec do
      def nothing
        asds = Asd.where
        asds.each &:custom_destroy
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    exprs = ast.expr.exprs
    assert_equal ASTAssignment, exprs[0].class
    assert_equal 'asds',        exprs[0].var_name.text
    assert_equal ASTSubset,     exprs[0].expr.class

    assert_equal ASTForEach,      exprs[1].class
    assert_equal 'e',             exprs[1].var_name.text
    assert_equal ASTVariableRead, exprs[1].objset.class
    assert_equal 'asds',          exprs[1].objset.var_name.text
    assert_equal ASTBlock,        exprs[1].expr.class

    loop_body = exprs[1].expr.exprs
    assert_equal 4, loop_body.length
    loop_body[0..2].each do |stmt|
      assert_equal ASTDeleteObj, stmt.class
    end
    assert_equal ASTEmptyObjset, loop_body[3].class
  end

  def test_extract__bool_vars_unsupported
    AsdsController.class_exec do
      def nothing
        @asd1 = Asd.where
        @asd2 = true
        @asd3 = Asd.find
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)

    exprs = ast.expr.exprs

    assert_equal 2, exprs.length
    
    assert_equal ASTAssignment, exprs[0].class
    assert_equal 'at__asd1',    exprs[0].var_name.text
    assert_equal ASTSubset,     exprs[0].expr.class
    
    assert_equal ASTAssignment, exprs[1].class
    assert_equal 'at__asd3',    exprs[1].var_name.text
    assert_equal ASTOneOf,      exprs[1].expr.class
  end

  def test_extract__empty_foreach_can_be_forced
    old_setting = ADSL::Lang::ASTForEach.include_empty_loops?
    
    AsdsController.class_exec do
      def nothing
        Asd.where.each do |asd|
        end
      end
    end

    extractor = create_rails_extractor
    
    ADSL::Lang::ASTForEach.include_empty_loops = false
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    assert_equal ast.expr.class, ASTEmptyObjset

    ADSL::Lang::ASTForEach.include_empty_loops = true
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    assert_equal ast.expr.class, ASTForEach
  ensure
    ADSL::Lang::ASTForEach.include_empty_loops = old_setting
  end
end
