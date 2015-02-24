require 'adsl/translation/ds_extensions'
require 'adsl/translation/ds_translator'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/type_sig'
require 'adsl/fol/first_order_logic'
require 'adsl/parser/adsl_parser.tab'
require 'minitest/unit'

require 'minitest/autorun'
require 'pp'

class ADSL::Translation::TranslationDSExtensionsTest < MiniTest::Unit::TestCase
  include ADSL::FOL

  def setup_class_test
    @t = ADSL::Translation::DSTranslator.new
    @parent  = ADSL::DS::DSClass.new :name => 'Parent'
    @child1  = ADSL::DS::DSClass.new :name => 'Child1', :parents => [@parent]
    @child2  = ADSL::DS::DSClass.new :name => 'Child2', :parents => [@parent]
    @diamond = ADSL::DS::DSClass.new :name => 'Diamond', :parents => [@child1, @child2]

    [@parent, @child1, @diamond, @child2].each do |c|
      c.translate @t
    end
  end
  
  def test_class__predicates_set
    setup_class_test

    assert_equal 'ParentSort', @parent.to_sort.name
    assert_equal @parent.to_sort, @child1.to_sort
    assert_equal @parent.to_sort, @child2.to_sort
    assert_equal @parent.to_sort, @diamond.to_sort

    assert_equal PredicateCall.new(@parent.type_pred, :a), @parent[:a]
    assert_not_equal @parent_type_pred, @parent.to_sort
    assert_equal PredicateCall.new(@child1.type_pred, :a), @child1[:a]
    assert_equal PredicateCall.new(@child2.type_pred, :a), @child2[:a]
    assert_equal PredicateCall.new(@diamond.type_pred, :a), @diamond[:a]
  end

  def test_type_sig__bracket_operator
    setup_class_test

    assert_equal PredicateCall.new(@parent.type_pred, :a), @parent.to_sig[:a]
    assert_equal PredicateCall.new(@child1.type_pred, :a), @child1.to_sig[:a]
    assert_equal PredicateCall.new(@child2.type_pred, :a), @child2.to_sig[:a]
    assert_equal PredicateCall.new(@diamond.type_pred, :a), @diamond.to_sig[:a]
    
    p_c = ADSL::DS::TypeSig::ObjsetType.new(@parent, @child1)
    assert_equal PredicateCall.new(@child1.type_pred, :a), p_c[:a]
  
    c1_c2 = ADSL::DS::TypeSig::ObjsetType.new(@child1, @child2)
    assert_equal(
      And[PredicateCall[@child1.type_pred, :a], PredicateCall[@child2.type_pred, :a]],
      c1_c2[:a]
    )
  end

  def test_generate_problems_basic
    spec = ADSL::Parser::ADSLParser.new.parse <<-adsl
      authenticable class Class1 {}
      usergroup UG
      class Class2 extends Class1 {}
      action blah() {
        create(Class1)
        delete allof(Class2)
      }
      invariant Inv1: true
      invariant Inv2: true
      permit UG edit allof(Class2)
    adsl
    problems = spec.generate_problems 'blah'
    assert_equal 4, problems.length
  end

  def test_generate_problems_invariant_simple
    spec = ADSL::Parser::ADSLParser.new.parse <<-adsl
      class Class {}
      action blah() {
        create(Class)
      }
      invariant true
    adsl
    problems = spec.generate_problems 'blah'
    assert_equal 1, problems.length
  end

  def test_generate_problems_simple_reads
    spec = ADSL::Parser::ADSLParser.new.parse <<-adsl
      authenticable class Class {}
      action blah() {
        x = allof(Class)
      }
    adsl
    problems = spec.generate_problems 'blah'
    assert_equal 1, problems.length
  end

  def test_generate_problems_reads_loops
    spec = ADSL::Parser::ADSLParser.new.parse <<-adsl
      authenticable class Class {}
      class Class2 {}
      action blah() {
        foreach v: allof(Class) {
          y = allof(Class2)
        }
        x = allof(Class)
      }
    adsl
    problems = spec.generate_problems 'blah'
    assert_equal 3, problems.length
  end

end

