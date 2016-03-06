require 'adsl/util/test_helper'
require 'adsl/lang/parser/adsl_parser.tab'
require 'adsl/lang/ast_nodes'
require 'set'

module ADSL::Lang
  module Parser
    class ClassParserTest < ActiveSupport::TestCase
  
      def test_class__empty
        parser = ADSLParser.new
        spec = parser.parse ""
        assert_equal([], spec.classes)
        assert_equal([], spec.actions)
      end
  
      def test_class__no_rels_and_order
        parser = ADSLParser.new
        spec = parser.parse <<-adsl
          class Kme {}
          class Zsd {}
          class Asd {}
        adsl
        assert_equal 3, spec.classes.length
        assert_equal ["Kme", "Zsd", "Asd"], spec.classes.map{ |a| a.name }
        spec.classes.each do |klass|
          assert_equal 0, klass.members.count
          assert klass.parents.empty?
        end
        assert_equal 0, spec.actions.count
      end
  
      def test_class__superclass
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class extends Unknown {}
          adsl
        end
        
        spec = parser.parse <<-adsl
          class Super {}
          class Sub extends Super {}
        adsl
        assert_equal 2, spec.classes.length
        assert spec.classes[0].parents.empty?
        assert_equal [spec.classes[0]], spec.classes[1].parents
        
        spec = parser.parse <<-adsl
          class Sub extends Super {}
          class Super {}
        adsl
        assert_equal 2, spec.classes.length
        assert spec.classes[1].parents.empty?
        assert_equal [spec.classes[1]], spec.classes[0].parents
  
        spec = parser.parse <<-adsl
          class Super1 {}
          class Super2 {}
          class Sub extends Super1, Super2 {}
        adsl
        assert_equal 3, spec.classes.length
        assert spec.classes[0].parents.empty?
        assert spec.classes[1].parents.empty?
        assert_equal [spec.classes[0], spec.classes[1]], spec.classes[2].parents
        
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class extends Class {}
          adsl
        end
        
        assert_raises ADSLError do
          parser.parse <<-adsl
            class First extends Class1 {}
            class Class2 extends Class1 {}
            class Class1 extends Class2 {}
          adsl
        end
      end
  
      def test_typecheck__rels_valid
        parser = ADSLParser.new
        spec = parser.parse <<-adsl
          class Classname {
            1 Classname other
            1 Classname something_else
            1 Classname third
          }
        adsl
  
        klass = spec.classes.select{ |a| a.name == "Classname" }.first
        assert klass
        assert_equal 3, klass.members.count
        assert_equal 'other', klass.members[0].name
        assert_equal 'something_else', klass.members[1].name
        assert_equal 'third', klass.members[2].name
        klass.members.each do |rel|
          assert rel.inverse_of.nil?
        end
      end
  
      def test_typecheck__inverse_rels_valid
        parser = ADSLParser.new
        spec = parser.parse <<-adsl
          class Classname {
            1 Classname other
            1 Classname something_else inverseof other
          }
        adsl
  
        klass = spec.classes.select{ |a| a.name == "Classname" }.first
        assert klass
        assert_equal 2, klass.members.count
        assert_equal 1, klass.members.select{ |a| a.inverse_of.nil? }.length
        assert_equal 1, klass.members.select{ |a| not a.inverse_of.nil? }.length
        other = klass.members.select{ |a| a.name == 'other'}.first
        something_else = klass.members.select{ |a| a.name == 'something_else'}.first
        assert_equal other, something_else.inverse_of
        
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Classname {
              1 Classname something_else inverseof other
              1 Classname other
            }
          adsl
        end
        
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Classname1 {
              1 Classname2 something_else inverseof other
            }
            class Classname2 {
              1 Classname1 other
            }
          adsl
        end
      end
  
      def test_typecheck__relation_cardinality_valid
        parser = ADSLParser.new
        spec = parser.parse <<-adsl
          class Classname {
            1 Classname other1
            1..1 Classname other2
            0..1 Classname other3
            0+ Classname other4
            1+ Classname other5
          }
        adsl
  
        klass = spec.classes.select{ |a| a.name == "Classname" }.first
        assert klass
        assert_equal ADSL::DS::TypeSig::ObjsetCardinality::ONE,       klass.members[0].cardinality
        assert_equal ADSL::DS::TypeSig::ObjsetCardinality::ONE,       klass.members[1].cardinality
        assert_equal ADSL::DS::TypeSig::ObjsetCardinality::ZERO_ONE,  klass.members[2].cardinality
        assert_equal ADSL::DS::TypeSig::ObjsetCardinality::ZERO_MANY, klass.members[3].cardinality
        assert_equal ADSL::DS::TypeSig::ObjsetCardinality::ONE_MANY,  klass.members[4].cardinality
      end
  
      def test_typecheck__relation_cardinality_invalid
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {
              0 Classname other
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {
              0..0 Classname other
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {
              1..0 Classname other
            }
          adsl
        end
      end
  
      def test_typecheck__repeating_classname
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {}
            class Classname {}
          adsl
        end 
      end
  
      def test_typecheck__unknown_rel_type
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {
              1 UnknownClass other
            }
          adsl
        end
      end
      
      def test_typecheck__mulitple_rels_under_the_same_name
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {
              1 Classname other
              1 Classname other
            }
          adsl
        end
      end
  
      def test_typecheck__multiple_rels_same_name_different_classes
        parser = ADSLParser.new
        assert_nothing_raised do
          parser.parse <<-adsl
            class Classname {
              1 Classname other
            }
            class Classname2 {
              1 Classname other
            }
          adsl
        end
      end
  
      def test_typecheck__multiple_rels_same_name_parent_classes
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Parent {
              1 Parent other
            }
            class Child extends Parent {
              1 Parent other2
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Parent {
              1 Parent other
            }
            class Child extends Parent {
              1 Parent other
            }
          adsl
        end
      end
  
      def test_typecheck__inverse_rel_of_unexisting
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {
              1 Classname other
              1 Classname other2 inverseof unexisting
            }
          adsl
        end
      end
      
      def test_typecheck__inverse_rel_of_an_inverse
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {
              1 Classname other inverseof other
            }
          adsl
        end 
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Classname {
              0+ Classname rel1 inverseof rel2
              0+ Classname rel2 inverseof rel1
            }
          adsl
        end 
      end
  
    end
  end
end
