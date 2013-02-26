require "parser/adsl_parser.tab"
require "test/unit"
require 'pp'
require 'set'

class ClassParserTest < Test::Unit::TestCase
  def test_class__empty
    parser = ADSL::ADSLParser.new
    spec = parser.parse ""
    assert_equal([], spec.classes)
    assert_equal([], spec.actions)
  end

  def test_class__no_rels_and_order
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-adsl
      class Kme {}
      class Zsd {}
      class Asd {}
    adsl
    assert_equal 3, spec.classes.length
    assert_equal ["Kme", "Zsd", "Asd"], spec.classes.map{ |a| a.name }
    spec.classes.each do |klass|
      assert_equal 0, klass.relations.count
      assert_nil klass.parent
    end
    assert_equal 0, spec.actions.count
  end

  def test_class__superclass
    parser = ADSL::ADSLParser.new
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Class extends Unknown {}
      adsl
    end
    
    spec = parser.parse <<-adsl
      class Super {}
      class Sub extends Super {}
    adsl
    assert_equal 2, spec.classes.length
    assert_nil spec.classes[0].parent
    assert_equal spec.classes[0], spec.classes[1].parent
    
    spec = parser.parse <<-adsl
      class Sub extends Super {}
      class Super {}
    adsl
    assert_equal 2, spec.classes.length
    assert_nil spec.classes[1].parent
    assert_equal spec.classes[1], spec.classes[0].parent

    begin
      parser.parse <<-adsl
        class Class extends Class {}
      adsl
      flunk "No error raised"
    rescue ADSL::ADSLError => e
      assert e.message.include? 'Class -> Class'
    end
    
    begin
      parser.parse <<-adsl
        class First extends Class1 {}
        class Class2 extends Class1 {}
        class Class1 extends Class2 {}
      adsl
      flunk "No error raised"
    rescue ADSL::ADSLError => e
      assert e.message.include? 'Class1 -> Class2'
    end
  end

  def test_typecheck__rels_valid
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-adsl
      class Classname {
        1 Classname other
        1 Classname something_else
        1 Classname third
      }
    adsl

    klass = spec.classes.select{ |a| a.name == "Classname" }.first
    assert klass
    assert_equal 3, klass.relations.count
    assert_equal 'other', klass.relations[0].name
    assert_equal 'something_else', klass.relations[1].name
    assert_equal 'third', klass.relations[2].name
    klass.relations.each do |rel|
      assert rel.inverse_of.nil?
    end
  end

  def test_typecheck__inverse_rels_valid
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-adsl
      class Classname {
        1 Classname other
        1 Classname something_else inverseof other
      }
    adsl

    klass = spec.classes.select{ |a| a.name == "Classname" }.first
    assert klass
    assert_equal 2, klass.relations.count
    assert_equal 1, klass.relations.select{ |a| a.inverse_of.nil? }.length
    assert_equal 1, klass.relations.select{ |a| not a.inverse_of.nil? }.length
    other = klass.relations.select{ |a| a.name == 'other'}.first
    something_else = klass.relations.select{ |a| a.name == 'something_else'}.first
    assert_equal other, something_else.inverse_of
    
    assert_nothing_raised ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          1 Classname something_else inverseof other
          1 Classname other
        }
      adsl
    end
    
    assert_nothing_raised ADSL::ADSLError do
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
    parser = ADSL::ADSLParser.new
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
    assert_equal [1, 1], klass.relations[0].cardinality
    assert_equal [1, 1], klass.relations[1].cardinality
    assert_equal [0, 1], klass.relations[2].cardinality
    assert_equal [0, 1.0/0.0], klass.relations[3].cardinality
    assert_equal [1, 1.0/0.0], klass.relations[4].cardinality
  end

  def test_typecheck__relation_cardinality_invalid
    parser = ADSL::ADSLParser.new
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          0 Classname other
        }
      adsl
    end
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          0..0 Classname other
        }
      adsl
    end
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          1..0 Classname other
        }
      adsl
    end
  end

  def test_typecheck__repeating_classname
    parser = ADSL::ADSLParser.new
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {}
        class Classname {}
      adsl
    end 
  end

  def test_typecheck__unknown_rel_type
    parser = ADSL::ADSLParser.new
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          1 UnknownClass other
        }
      adsl
    end
  end
  
  def test_typecheck__mulitple_rels_under_the_same_name
    parser = ADSL::ADSLParser.new
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          1 Classname other
          1 Classname other
        }
      adsl
    end
  end

  def test_typecheck__multiple_rels_same_name_different_classes
    parser = ADSL::ADSLParser.new
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
    parser = ADSL::ADSLParser.new
    assert_nothing_raised ADSL::ADSLError do
      parser.parse <<-adsl
        class Parent {
          1 Parent other
        }
        class Child extends Parent {
          1 Parent other2
        }
      adsl
    end
    assert_raise ADSL::ADSLError do
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
    parser = ADSL::ADSLParser.new
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          1 Classname other
          1 Classname other2 inverseof unexisting
        }
      adsl
    end
  end
  
  def test_typecheck__inverse_rel_of_an_inverse
    parser = ADSL::ADSLParser.new
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          1 Classname other inverseof other
        }
      adsl
    end 
    assert_raise ADSL::ADSLError do
      parser.parse <<-adsl
        class Classname {
          0+ Classname rel1 inverseof rel2
          0+ Classname rel2 inverseof rel1
        }
      adsl
    end 
  end

end
