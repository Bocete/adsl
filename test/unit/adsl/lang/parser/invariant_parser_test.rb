require 'adsl/util/test_helper'
require 'adsl/lang/parser/adsl_parser.tab'
require 'adsl/ds/data_store_spec'

module ADSL::Lang
  module Parser
    class InvariantParserTest < ActiveSupport::TestCase
      include ADSL::Lang::Parser
      include ADSL::DS
      
      def test_invariant__constants
        parser = ADSLParser.new
  
        [true, false].each do |bool|
          spec = nil
          assert_nothing_raised ADSLError do
            spec = parser.parse "invariant #{bool.to_s}"
          end
          assert_equal([], spec.actions)
          assert_equal([], spec.classes)
          assert_equal 1, spec.invariants.length
          assert_equal bool, spec.invariants.first.formula.value
        end
      end
  
      def test_invariant__names
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse "invariant some_name: true"
        end
        assert_equal "some_name", spec.invariants.first.name
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            invariant some_name: true
            invariant true
          ADSL
        end
        
        assert_raises ADSLError do
          spec = parser.parse <<-ADSL
            invariant some_name: true
            invariant some_name: true
          ADSL
        end
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            invariant true
            invariant true
          ADSL
        end
        assert_equal "unnamed_line_1", spec.invariants.first.name
        assert_equal "unnamed_line_2", spec.invariants.last.name
      end
      
      def test_invariant__forall_and_exists_one_param
        parser = ADSLParser.new
  
        operators = {
          "forall" => DSForAll,
          "exists" => DSExists
        }
        
        operators.each do |word, type|
          spec = nil
          assert_nothing_raised ADSLError do
            spec = parser.parse <<-ADSL
              class Class {}
              invariant #{word}(Class a: true)
            ADSL
          end
          invariant = spec.invariants.first
          assert_equal type, invariant.formula.class
          assert_equal 1, invariant.formula.vars.length
          assert_equal spec.classes.first.to_sig, invariant.formula.vars.first.type_sig
          assert_equal 'a', invariant.formula.vars.first.name
          assert_equal true, invariant.formula.subformula.value
        end 
      end
  
      def test_invariant__forall_and_exists_multiple_params
        parser = ADSLParser.new
        
        operators = {
          "forall" => DSForAll,
          "exists" => DSExists
        }
        
        operators.each do |word, type|
          spec = nil
          assert_nothing_raised ADSLError do
            spec = parser.parse <<-ADSL
              class Class {}
              invariant #{word}(Class a, Class b: true)
            ADSL
          end
          invariant = spec.invariants.first
          assert_equal type, invariant.formula.class
          assert_equal 2, invariant.formula.vars.length
          assert_equal [spec.classes.first.to_sig, spec.classes.first.to_sig], invariant.formula.vars.map(&:type_sig)
          assert_equal ['a', 'b'], invariant.formula.vars.map{ |v| v.name }
          assert_equal true, invariant.formula.subformula.value
        end 
      end
  
      def test_invariant__forall_and_exists_typecheck
        parser = ADSLParser.new
        
        ['forall', 'exists'].each do |formula|
          assert_raises ADSLError do
            parser.parse <<-ADSL
              invariant #{formula}(true)
            ADSL
          end
          assert_raises ADSLError do
            parser.parse <<-ADSL
              invariant #{formula}(Class a, Class b: true)
            ADSL
          end
          assert_raises ADSLError do
            parser.parse <<-ADSL
              class Class {}
              invariant #{formula}(Class a, Class a: true)
            ADSL
          end  
          assert_raises ADSLError do
            parser.parse <<-ADSL
              class Class {}
              invariant #{formula}(Class a: #{formula}(Class a: true))
            ADSL
          end  
        end
      end

      def test_invariant__isempty_equals_precedence
        parser = ADSLParser.new
        spec = parser.parse <<-ADSL
          class Class {}
          class Class2 {}
          invariant isempty(Class) == isempty(Class2)
        ADSL

        invariant = spec.invariants.first
        assert_equal DSEqual, invariant.formula.class
        assert_equal DSIsEmpty, invariant.formula.exprs[0].class
        assert_equal DSIsEmpty, invariant.formula.exprs[1].class
      end
  
      def test_invariant__forall_and_exists_can_use_objsets
        parser = ADSLParser.new
        ['forall', 'exists'].each do |formula|
          spec = parser.parse <<-ADSL
            class Class { 0+ Class relation }
            invariant #{formula}(a in allof(Class): true)
          ADSL
          invariant = spec.invariants.first
          assert_equal 'a', invariant.formula.vars.first.name
          assert_equal DSAllOf, invariant.formula.objsets.first.class
          
          spec = parser.parse <<-ADSL
            class Class { 0+ Class relation }
            invariant #{formula}(a in allof(Class).relation: true)
          ADSL
          invariant = spec.invariants.first
          assert_equal 'a', invariant.formula.vars.first.name
          assert_equal DSDereference, invariant.formula.objsets.first.class
          
          spec = parser.parse <<-ADSL
            class Class { 0+ Class relation }
            invariant #{formula}(Class a: #{formula}(b in a: true))
          ADSL
        end
      end
  
      def test_invariant__exists_can_go_without_subformula_while_forall_cannot
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            invariant exists(Class a)
          ADSL
        end
        assert_raises ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            invariant forall(Class a)
          ADSL
        end
      end
  
      def test_invariant__parenthesis
        parser = ADSLParser.new
        spec = parser.parse <<-ADSL
          invariant (true)
        ADSL
        invariant = spec.invariants.first
        assert_equal true, invariant.formula.value
      end
  
      def test_invariant__not
        parser = ADSLParser.new
        ['not', '!'].each do |word|
          spec = parser.parse <<-ADSL
            invariant not false
          ADSL
          invariant = spec.invariants.first
          assert_equal DSNot, invariant.formula.class
          assert_equal false, invariant.formula.subformula.value
        end
      end
  
      def test_invariant__and_or
        parser = ADSLParser.new
        operators = {
          "and" => DSAnd, 
          "or" => DSOr 
        }
        operators.each do |word, type|
          spec = parser.parse <<-ADSL
            invariant * #{word} *
          ADSL
          invariant = spec.invariants.first
          assert_equal type, invariant.formula.class
          assert_equal [nil, nil], invariant.formula.subformulae.map{ |a| a.value}
        end
      end
  
      def test_invariant__operator_precedence_and_associativity
        parser = ADSLParser.new
        operators = {
          "and" => DSAnd, 
          "or" => DSOr 
        }
        operators.each do |word, type|
          spec = parser.parse <<-ADSL
            invariant not true #{word} false
          ADSL
          invariant = spec.invariants.first
          assert_equal type, invariant.formula.class
          assert_equal DSNot, invariant.formula.subformulae.first.class
          assert_equal false, invariant.formula.subformulae.second.value
        end
        operators.each do |word, type|
          spec = parser.parse <<-ADSL
            invariant not (true #{word} false)
          ADSL
          invariant = spec.invariants.first
          assert_equal DSNot, invariant.formula.class
          assert_equal type, invariant.formula.subformula.class
        end
        spec = parser.parse <<-ADSL
          invariant true and !false or true
        ADSL
        invariant = spec.invariants.first
        assert_equal DSOr, invariant.formula.class
        assert_equal true, invariant.formula.subformulae.second.value
        assert_equal DSAnd, invariant.formula.subformulae.first.class
        assert_equal true, invariant.formula.subformulae.first.subformulae.first.value
        assert_equal DSNot, invariant.formula.subformulae.first.subformulae.second.class
      end
  
      def test_invariant__equal
        parser = ADSLParser.new
        spec = parser.parse <<-ADSL
          class Class {}
          invariant exists(Class o1, Class o2: o1 == o2)
        ADSL
        f = spec.invariants.first.formula.subformula
        assert_equal DSEqual, f.class
        assert_equal ['o1', 'o2'], f.exprs.map { |v| v.variable.name }
  
        spec = parser.parse <<-ADSL
          class Class {}
          invariant exists(Class o1, Class o2: equal(o1, o2))
        ADSL
        f = spec.invariants.first.formula.subformula
        assert_equal DSEqual, f.class
        assert_equal ['o1', 'o2'], f.exprs.map { |v| v.variable.name }
  
        spec = parser.parse <<-ADSL
          class Class {}
          invariant exists(Class o1, Class o2: equal(o1, o2, o1, o1))
        ADSL
        f = spec.invariants.first.formula.subformula
        assert_equal DSEqual, f.class
        assert_equal ['o1', 'o2', 'o1', 'o1'], f.exprs.map { |v| v.variable.name }
  
        assert_nothing_raised ADSLError do
          parser.parse <<-ADSL
            class Class {}
            class Child extends Class {}
            invariant allof(Class) == allof(Child)
          ADSL
        end
        assert_raises ADSLError do
          parser.parse <<-ADSL
            class Class1 {}
            class Class2 {}
            invariant allof(Class1) == allof(Child2)
          ADSL
        end
        assert_raises ADSLError do
          parser.parse <<-ADSL
            class Parent {}
            class Class1 extends Parent {}
            class Class2 extends Parent {}
            invariant equal(allof(Parent), allof(Class1), allof(Child2))
          ADSL
        end
      end
  
      def test_invariant__not_equal
        parser = ADSLParser.new
        spec = parser.parse <<-ADSL
          class Class {}
          invariant exists(Class o1, Class o2: o1 != o2)
        ADSL
        f = spec.invariants.first.formula.subformula
        assert_equal DSNot, f.class
        assert_equal DSEqual, f.subformula.class
        assert_equal ['o1', 'o2'], f.subformula.exprs.map { |v| v.variable.name }
      end
      
      def test_invariant__equiv
        parser = ADSLParser.new
        spec = parser.parse <<-ADSL
          class Class {}
          invariant true <=> false
        ADSL
        invariant = spec.invariants.first
        assert_equal DSEqual, invariant.formula.class
        assert_equal [true, false], invariant.formula.exprs.map{ |f| f.value }
        
        spec = parser.parse <<-ADSL
          class Class {}
          invariant equal(true, false)
        ADSL
        invariant = spec.invariants.first
        assert_equal DSEqual, invariant.formula.class
        assert_equal [true, false], invariant.formula.exprs.map{ |f| f.value }
        
        spec = parser.parse <<-ADSL
          class Class {}
          invariant equal(true, false, true, true)
        ADSL
        invariant = spec.invariants.first
        assert_equal DSEqual, invariant.formula.class
        assert_equal [true, false, true, true], invariant.formula.exprs.map{ |f| f.value }
      end
  
      def test_invariant__implies
        parser = ADSLParser.new
        spec = parser.parse <<-ADSL
          class Class {}
          invariant true => false
        ADSL
        invariant = spec.invariants.first
        assert_equal DSImplies, invariant.formula.class
        assert_equal true,  invariant.formula.subformula1.value
        assert_equal false, invariant.formula.subformula2.value
        
        spec = parser.parse <<-ADSL
          class Class {}
          invariant false <= true
        ADSL
        invariant = spec.invariants.first
        assert_equal DSImplies, invariant.formula.class
        assert_equal true,  invariant.formula.subformula1.value
        assert_equal false, invariant.formula.subformula2.value
        
        spec = parser.parse <<-ADSL
          class Class {}
          invariant implies(true, false)
        ADSL
        invariant = spec.invariants.first
        assert_equal DSImplies, invariant.formula.class
        assert_equal true,  invariant.formula.subformula1.value
        assert_equal false, invariant.formula.subformula2.value
      end
      
      def test_invariant__empty
        parser = ADSLParser.new
        spec = parser.parse <<-ADSL
          class Class {}
          invariant isempty(allof(Class))
        ADSL
        invariant = spec.invariants.first
        assert_equal DSIsEmpty, invariant.formula.class
        assert_equal DSAllOf, invariant.formula.objset.class
      end
  
      def test_invariant__in
        parser = ADSLParser.new
        spec = parser.parse <<-ADSL
          class Class {}
          invariant allof(Class) in allof(Class)
        ADSL
        invariant = spec.invariants.first
        assert_equal DSIn, invariant.formula.class
        assert_equal DSAllOf, invariant.formula.objset1.class
        assert_equal DSAllOf, invariant.formula.objset2.class
  
        assert_raises ADSLError do
          parser.parse <<-ADSL
            class Class1 {}
            class Class2 {}
            invariant allof(Class1) in allof(Class2)
          ADSL
        end
        assert_raises ADSLError do
          parser.parse <<-ADSL
            class Super {}
            class Sub extends Super {}
            invariant allof(Super) in allof(Sub)
          ADSL
        end
        assert_nothing_raised ADSLError do
          parser.parse <<-ADSL
            class Super {}
            class Sub extends Super {}
            invariant allof(Sub) in allof(Super)
          ADSL
        end
      end
  
      def test_invariant__variable_scope
        parser = ADSLParser.new
        parser.parse <<-ADSL
          class Class {}
          invariant exists(Class o)
          invariant exists(Class o)
          invariant exists(Class o)
          invariant exists(Class o)
        ADSL
      end
  
      def test_invariant__no_side_effects
        parser = ADSLParser.new
        assert_nothing_raised do
          parser.parse <<-ADSL
            class Class {}
            invariant exists(o in allof(Class))
          ADSL
        end
        assert_raises ADSLError do
          parser.parse <<-ADSL
            class Class {}
            invariant exists(o in create(Class))
          ADSL
        end
        assert_raises ADSLError do
          parser.parse <<-ADSL
            class Class {}
            invariant exists(o in a = allof(Class))
          ADSL
        end
      end
    end
  end
end

