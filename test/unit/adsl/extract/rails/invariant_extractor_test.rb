require 'adsl/util/test_helper'
require 'adsl/extract/rails/invariant_extractor'
require 'adsl/extract/rails/rails_instrumentation_test_case'
require 'adsl/lang/ast_nodes'

module ADSL::Extract::Rails
  class InvariantExtractorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase

    include ADSL::Lang

    def test_load_in_context__basic
      invariant_string = <<-invariants
        invariant "blah", true
        invariant true
      invariants
      
      ie = InvariantExtractor.new ar_class_names
      ie.extract invariant_string
      assert_equal 2, ie.invariants.length

      assert_equal 'blah', ie.invariants[0].description
      assert_equal true,   ie.invariants[0].formula.bool_value

      assert_equal nil,    ie.invariants[1].description
      assert_equal true,   ie.invariants[1].formula.bool_value
    end
    
    def test_load_in_context__forall_works
      invariant_string = <<-invariants
        invariant 'first', forall{ |asd|
          asd.empty?
        }
      invariants
      initialize_metaclasses

      ie = InvariantExtractor.new ar_class_names
      ie.extract invariant_string
      assert_equal 1, ie.invariants.length

      assert_equal 'first',    ie.invariants[0].description
      assert_equal ASTForAll,  ie.invariants[0].formula.class
      assert_equal ASTIsEmpty, ie.invariants[0].formula.subformula.class
    end

    def test_load_in_context__do_end_moved_to_parameter
      invariant_string = <<-invariants
        invariant 'first', forall{ |asd|
          asd.empty?
        }
        invariant 'second', forall do |asd|
          asd.empty?
        end
      invariants
      initialize_metaclasses

      ie = InvariantExtractor.new ar_class_names
      ie.extract invariant_string
      assert_equal 2, ie.invariants.length

      assert_equal 'first',    ie.invariants[0].description
      assert_equal ASTForAll,  ie.invariants[0].formula.class
      assert_equal ASTIsEmpty, ie.invariants[0].formula.subformula.class

      assert_equal 'second',   ie.invariants[1].description
      assert_equal ASTForAll,  ie.invariants[1].formula.class
      assert_equal ASTIsEmpty, ie.invariants[1].formula.subformula.class
    end
    
    def test_load_in_context__instrumented_ar_classes
      initialize_metaclasses

      invariant_string = <<-invariants
        invariant Asd.all.kmes.empty?
      invariants
      
      ie = InvariantExtractor.new ar_class_names
      ie.extract invariant_string
      assert_equal 1, ie.invariants.length

      inv = ie.invariants.first.formula

      assert_equal ASTIsEmpty,      inv.class
      assert_equal ASTMemberAccess, inv.objset.class
      assert_equal 'kme12',         inv.objset.member_name.text
      assert_equal ASTMemberAccess, inv.objset.objset.class
      assert_equal 'blahs',         inv.objset.objset.member_name.text
      assert_equal ASTAllOf,        inv.objset.objset.objset.class
    end

    def test_load_in_context__instrumented_boolean_operators
      invariant_string = <<-invariants
        invariant((!true) && false)
      invariants

      ie = InvariantExtractor.new ar_class_names
      ie.extract invariant_string
      assert_equal 1, ie.invariants.length

      assert_equal ASTAnd,     ie.invariants[0].formula.class
      assert_equal ASTNot, ie.invariants[0].formula.subformulae[0].class
      assert_equal ASTBoolean, ie.invariants[0].formula.subformulae[0].subformula.class
      assert_equal true, ie.invariants[0].formula.subformulae[0].subformula.bool_value
      
      assert_equal ASTBoolean, ie.invariants[0].formula.subformulae[1].class
      assert_equal false, ie.invariants[0].formula.subformulae[1].bool_value
    end
  end
end
