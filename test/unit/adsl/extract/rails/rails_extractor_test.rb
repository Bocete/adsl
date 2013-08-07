require 'test/unit'
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
    assert_equal ASTObjsetStmt, statements.first.class
    assert_equal ASTCreateObjset, statements.first.objset.class
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
    assert_equal ASTObjsetStmt, statements.first.class
    assert_equal ASTCreateObjset, statements.first.objset.class
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
    assert_equal ASTAssignment, statements.first.class
    assert_equal 'a', statements.first.var_name.text
    assert_equal ASTCreateObjset, statements.first.objset.class
    assert_equal 'Asd', statements.first.objset.class_name.text
  end

  def test_action_extraction__instance_variable_assignment
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

    assert_false statements.empty?
    assert_equal 3, statements.length

    assert_equal ASTAssignment, statements.first.class
    assert_equal 'at__a', statements.first.var_name.text
    assert_equal ASTCreateObjset, statements.first.objset.class
    assert_equal 'Asd', statements.first.objset.class_name.text

    assert_equal ASTAssignment, statements.second.class
    assert_equal 'a', statements.second.var_name.text

    assert_equal ASTDeleteObj, statements.last.class
    assert_equal 'at__a', statements.last.objset.var_name.text
  end
  
  def test_action_extraction__class_variable_assignment
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

    assert_false statements.empty?
    assert_equal 4, statements.length

    assert_equal ASTAssignment, statements.first.class
    assert_equal 'atat__a', statements.first.var_name.text
    assert_equal ASTCreateObjset, statements.first.objset.class
    assert_equal 'Asd', statements.first.objset.class_name.text

    assert_equal ASTAssignment, statements[1].class
    assert_equal 'a', statements[1].var_name.text
    assert_equal ASTAssignment, statements[2].class
    assert_equal 'at__a', statements[2].var_name.text
    
    assert_equal ASTDeleteObj, statements.last.class
    assert_equal 'atat__a', statements.last.objset.var_name.text
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
    assert_equal ASTCreateObjset, either.blocks.first.statements.first.objset.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ASTDeleteObj, either.blocks.second.statements.first.class
  end

  def test_action_extraction__one_returning_branch
    AsdsController.class_exec do
      def nothing
        if something
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
    assert_equal 2, either.blocks.first.statements.length
    assert_equal ASTCreateObjset, either.blocks.first.statements.first.objset.class
    assert_equal ASTDeleteObj, either.blocks.first.statements.second.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ASTCreateObjset, either.blocks.second.statements.first.objset.class
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
    assert_equal ASTObjsetStmt, statements.first.class
    assert_equal ASTCreateObjset, statements.first.objset.class
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
    assert_equal ASTObjsetStmt, statements.first.class
    assert_equal ASTCreateObjset, statements.first.objset.class
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
    assert_equal ASTEither, statements.first.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 1, either.blocks.first.statements.length
    assert_equal ASTCreateObjset, either.blocks.first.statements.first.objset.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ASTCreateObjset, either.blocks.second.statements.first.objset.class
  end
  
  def test_action_extraction__calls_of_method_with_multiple_paths
    AsdsController.class_exec do
      def something
        if whatever
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
    assert_equal ASTCreateObjset, statements.second.objset.class

    either = statements.first

    assert_equal 2, either.blocks.length
    assert_equal 1, either.blocks.first.statements.length
    assert_equal ASTDeleteObj, either.blocks.first.statements.first.class
    assert_equal 1, either.blocks.second.statements.length
    assert_equal ASTCreateObjset, either.blocks.second.statements.first.objset.class
  end

  def test_action_extraction__multiple_return
    AsdsController.class_exec do
      def blah
        return Asd.new, Kme.new
      end
      
      def nothing
        blah
        raise 'Not returned properly' unless vals.length == 2
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length

    assert_equal ASTCreateObjset, statements.first.objset.class
    assert_equal 'Asd', statements.first.objset.class_name.text
    
    assert_equal ASTCreateObjset, statements.second.objset.class
    assert_equal 'Kme', statements.second.objset.class_name.text
  end

  def test_action_extraction__multiple_assignment
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

    assert_equal ASTAssignment, statements[0].class
    assert_equal 'a', statements[0].var_name.text
    assert_equal ASTCreateObjset, statements[0].objset.class
    assert_equal 'Asd', statements[0].objset.class_name.text
    
    assert_equal ASTAssignment, statements[1].class
    assert_equal 'b', statements[1].var_name.text
    assert_equal ASTCreateObjset, statements[1].objset.class
    assert_equal 'Kme', statements[1].objset.class_name.text
    
    assert_equal ASTDeleteObj, statements[2].class
    assert_equal 'a', statements[2].objset.var_name.text
    
    assert_equal ASTDeleteObj, statements[3].class
    assert_equal 'b', statements[3].objset.var_name.text
  end

  def test_action_extraction__optional_assignment
    AsdsController.class_exec do
      def nothing
        a ||= Asd.new
        a = Kme.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 2, statements.length

    assert_equal ASTEither, statements[0].class
    assert_equal 1, statements[0].blocks[0].statements.length
    assert_equal 0, statements[0].blocks[1].statements.length
    assert_equal ASTAssignment,   statements[0].blocks[0].statements[0].class
    assert_equal 'a',             statements[0].blocks[0].statements[0].var_name.text
    assert_equal ASTCreateObjset, statements[0].blocks[0].statements[0].objset.class
    assert_equal 'Asd',           statements[0].blocks[0].statements[0].objset.class_name.text

    assert_equal ASTAssignment,   statements[1].class
    assert_equal 'a',             statements[1].var_name.text
    assert_equal ASTCreateObjset, statements[1].objset.class
    assert_equal 'Kme',            statements[1].objset.class_name.text
  end
  
  def test_action_extraction__multiple_assignment_of_return
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

    assert_equal ASTAssignment, statements[0].class
    assert_equal 'a', statements[0].var_name.text
    assert_equal ASTCreateObjset, statements[0].objset.class
    assert_equal 'Asd', statements[0].objset.class_name.text
    
    assert_equal ASTAssignment, statements[1].class
    assert_equal 'b', statements[1].var_name.text
    assert_equal ASTCreateObjset, statements[1].objset.class
    assert_equal 'Kme', statements[1].objset.class_name.text
    
    assert_equal ASTDeleteObj, statements[2].class
    assert_equal 'a', statements[2].objset.var_name.text
    
    assert_equal ASTDeleteObj, statements[3].class
    assert_equal 'b', statements[3].objset.var_name.text
  end

  def test_callback_lookup
    extractor = create_rails_extractor
    assert_set_equal(
      [:before, :after, :before2, :before_nothing, :after_nothing],
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
    assert_equal 'Asd', statements[0].objset.class_name.text
    assert_equal 'Kme', statements[1].objset.class_name.text
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
    assert_equal 'Kme', statements[0].objset.class_name.text
    assert_equal 'Asd', statements[1].objset.class_name.text
  end
  
  def test_before_callbacks__can_have_branches_normally
    AsdsController.class_exec do
      def before
        if whatever
          return Kme.new
        else
          Asd.new
        end
      end
      
      def before2
        if whatever
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
    assert_equal ASTObjsetStmt, blocks[0].statements[0].class
    assert_equal 'Asd',         blocks[0].statements[0].objset.class_name.text
    assert_equal 1,             blocks[1].statements.length
    assert_equal ASTObjsetStmt, blocks[1].statements[0].class
    assert_equal 'Kme',         blocks[1].statements[0].objset.class_name.text
    
    assert_equal ASTEither, statements[1].class
    assert_equal 2, statements[1].blocks.length
    blocks = statements[1].blocks
    assert_equal 1,             blocks[0].statements.length
    assert_equal ASTObjsetStmt, blocks[0].statements[0].class
    assert_equal 'Kme',         blocks[0].statements[0].objset.class_name.text
    assert_equal 0,             blocks[1].statements.length

    assert_equal ASTObjsetStmt, statements[2].class
    assert_equal 'Mod_Blah',    statements[2].objset.class_name.text
  end
  
  def test_after_callbacks__can_have_branches_normally
    AsdsController.class_exec do
      def after_filter_action
        Mod::Blah.new
      end
      
      def after
        if whatever
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
    
    assert_equal ASTObjsetStmt, statements[0].class
    assert_equal 'Mod_Blah',    statements[0].objset.class_name.text

    assert_equal ASTEither, statements[1].class
    assert_equal 2,         statements[1].blocks.length
    blocks = statements[1].blocks
    assert_equal 1,             blocks[0].statements.length
    assert_equal ASTObjsetStmt, blocks[0].statements[0].class
    assert_equal 'Asd',         blocks[0].statements[0].objset.class_name.text
    assert_equal 1,             blocks[1].statements.length
    assert_equal ASTObjsetStmt, blocks[1].statements[0].class
    assert_equal 'Kme',         blocks[1].statements[0].objset.class_name.text
  end

  def test_callbacks__multiple_branched_callbacks
    AsdsController.class_exec do
      def before_nothing
        if whatever
          return Kme.new
        else
          Asd.new
        end
      end

      def nothing
        if whatever
          Kme.new
        else
          return Kme.new
        end
      end

      def after_nothing
        if whatever
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

    expected_classnames = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |index|
      assert_equal ASTEither, statements[index].class
      blocks =                statements[index].blocks
      assert_equal 2,         blocks.length
      assert_equal 1,                          blocks[0].statements.length
      assert_equal ASTObjsetStmt,              blocks[0].statements[0].class
      assert_equal expected_classnames[index], blocks[0].statements[0].objset.class_name.text
      assert_equal 1,                          blocks[1].statements.length
      assert_equal ASTObjsetStmt,              blocks[1].statements[0].class
      assert_equal 'Kme',                      blocks[1].statements[0].objset.class_name.text
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

    assert_equal 0, statements.length
  end
  
  def test_before_callbacks__halt_callback_chain_when_rendering_sometimes
    AsdsController.class_exec do
      def before
        if something
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

    assert_equal 1, statements.length
    assert_equal ASTEither, statements[0].class

    blocks = statements[0].blocks
    assert_equal 2, blocks.length
    
    assert_equal 3, blocks[1].statements.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal ASTObjsetStmt,    blocks[1].statements[i].class
      assert_equal types[i],         blocks[1].statements[i].objset.class_name.text
    end

    assert_equal 1,     blocks[0].statements.length
    assert_equal 'Asd', blocks[0].statements[0].objset.class_name.text
  end

  def test_before_callbacks__affect_after
    AsdsController.class_exec do
      def before_nothing
        if something
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

    assert_equal 1, statements.length
    assert_equal ASTEither, statements[0].class

    blocks = statements[0].blocks
    assert_equal 2, blocks.length
    
    assert_equal 3, blocks[1].statements.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal ASTObjsetStmt,    blocks[1].statements[i].class
      assert_equal types[i],         blocks[1].statements[i].objset.class_name.text
    end

    assert_equal 1,     blocks[0].statements.length
    assert_equal 'Asd', blocks[0].statements[0].objset.class_name.text
  end

  def test_before_callbacks__render_in_action_does_not_halt_after
    AsdsController.class_exec do
      def before_nothing
        if something
          render
        end
        Asd.new
      end
      
      def nothing
        Kme.new
        instance_eval "render :text => 'blah'"
      end

      def after_nothing
        Mod::Blah.new
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    statements = ast.block.statements

    assert_equal 1, statements.length
    assert_equal ASTEither, statements[0].class

    blocks = statements[0].blocks
    assert_equal 2, blocks.length
    
    assert_equal 3, blocks[1].statements.length
    types = ['Asd', 'Kme', 'Mod_Blah']
    3.times do |i|
      assert_equal ASTObjsetStmt,    blocks[1].statements[i].class
      assert_equal types[i],         blocks[1].statements[i].objset.class_name.text
    end

    assert_equal 1,     blocks[0].statements.length
    assert_equal 'Asd', blocks[0].statements[0].objset.class_name.text
  end

end
