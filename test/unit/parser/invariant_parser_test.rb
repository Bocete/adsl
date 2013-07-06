require 'parser/adsl_parser.tab'
require 'ds/data_store_spec'
require 'test/unit'
require 'pp'

class InvariantParserTest < Test::Unit::TestCase
  def test_invariant__constants
    parser = ADSL::ADSLParser.new

    [true, false].each do |bool|
      spec = nil
      assert_nothing_raised ADSL::ADSLError do
        spec = parser.parse "invariant #{bool.to_s}"
      end
      assert_equal([], spec.actions)
      assert_equal([], spec.classes)
      assert_equal 1, spec.invariants.length
      assert_equal bool, spec.invariants.first.formula.bool_value
    end
  end

  def test_invariant__names
    parser = ADSL::ADSLParser.new
    spec = nil
    assert_nothing_raised ADSL::ADSLError do
      spec = parser.parse "invariant some_name: true"
    end
    assert_equal "some_name", spec.invariants.first.name
    
    assert_nothing_raised ADSL::ADSLError do
      spec = parser.parse <<-ADSL
        invariant some_name: true
        invariant true
      ADSL
    end
    
    assert_raise ADSL::ADSLError do
      spec = parser.parse <<-ADSL
        invariant some_name: true
        invariant some_name: true
      ADSL
    end
    
    assert_nothing_raised ADSL::ADSLError do
      spec = parser.parse <<-ADSL
        invariant true
        invariant true
      ADSL
    end
    assert_equal "unnamed_line_1", spec.invariants.first.name
    assert_equal "unnamed_line_2", spec.invariants.last.name
  end
  
  def test_invariant__forall_and_exists_one_param
    parser = ADSL::ADSLParser.new

    operators = {
      "forall" => DS::DSForAll,
      "exists" => DS::DSExists
    }
    
    operators.each do |word, type|
      spec = nil
      assert_nothing_raised ADSL::ADSLError do
        spec = parser.parse <<-ADSL
          class Class {}
          invariant #{word}(Class a: true)
        ADSL
      end
      invariant = spec.invariants.first
      assert_equal type, invariant.formula.class
      assert_equal 1, invariant.formula.vars.length
      assert_equal spec.classes.first, invariant.formula.vars.first.type
      assert_equal 'a', invariant.formula.vars.first.name
      assert_equal true, invariant.formula.subformula.bool_value
    end 
  end

  def test_invariant__forall_and_exists_mulitple_params
    parser = ADSL::ADSLParser.new
    
    operators = {
      "forall" => DS::DSForAll,
      "exists" => DS::DSExists
    }
    
    operators.each do |word, type|
      spec = nil
      assert_nothing_raised ADSL::ADSLError do
        spec = parser.parse <<-ADSL
          class Class {}
          invariant #{word}(Class a, Class b: true)
        ADSL
      end
      invariant = spec.invariants.first
      assert_equal type, invariant.formula.class
      assert_equal 2, invariant.formula.vars.length
      assert_equal [spec.classes.first, spec.classes.first], invariant.formula.vars.map{ |v| v.type }
      assert_equal ['a', 'b'], invariant.formula.vars.map{ |v| v.name }
      assert_equal true, invariant.formula.subformula.bool_value
    end 
  end

  def test_invariant__forall_and_exists_typecheck
    parser = ADSL::ADSLParser.new
    
    ['forall', 'exists'].each do |formula|
      assert_raise do
        parser.parse <<-ADSL
          invariant #{formula}(true)
        ADSL
      end
      assert_raise ADSL::ADSLError do
        parser.parse <<-ADSL
          invariant #{formula}(Class a, Class b: true)
        ADSL
      end
      assert_raise ADSL::ADSLError do
        parser.parse <<-ADSL
          class Class {}
          invariant #{formula}(Class a, Class a: true)
        ADSL
      end  
      assert_raise ADSL::ADSLError do
        parser.parse <<-ADSL
          class Class {}
          invariant #{formula}(Class a: #{formula}(Class a: true))
        ADSL
      end  
    end
  end

  def test_invariant__forall_and_exists_can_use_objsets
    parser = ADSL::ADSLParser.new
    ['forall', 'exists'].each do |formula|
      spec = parser.parse <<-ADSL
        class Class { 0+ Class relation }
        invariant #{formula}(a in allof(Class): true)
      ADSL
      invariant = spec.invariants.first
      assert_equal 'a', invariant.formula.vars.first.name
      assert_equal DS::DSAllOf, invariant.formula.objsets.first.class
      
      spec = parser.parse <<-ADSL
        class Class { 0+ Class relation }
        invariant #{formula}(a in allof(Class).relation: true)
      ADSL
      invariant = spec.invariants.first
      assert_equal 'a', invariant.formula.vars.first.name
      assert_equal DS::DSDereference, invariant.formula.objsets.first.class
      
      spec = parser.parse <<-ADSL
        class Class { 0+ Class relation }
        invariant #{formula}(Class a: #{formula}(b in a: true))
      ADSL
    end
  end

  def test_invariant__exists_can_go_without_subformula_while_forall_cannot
    parser = ADSL::ADSLParser.new
    assert_nothing_raised ADSL::ADSLError do
      spec = parser.parse <<-ADSL
        class Class {}
        invariant exists(Class a)
      ADSL
    end
    assert_raise do
      spec = parser.parse <<-ADSL
        class Class {}
        invariant forall(Class a)
      ADSL
    end
  end

  def test_invariant__parenthesis
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-ADSL
      invariant (true)
    ADSL
    invariant = spec.invariants.first
    assert_equal true, invariant.formula.bool_value
  end

  def test_invariant__not
    parser = ADSL::ADSLParser.new
    ['not', '!'].each do |word|
      spec = parser.parse <<-ADSL
        invariant not false
      ADSL
      invariant = spec.invariants.first
      assert_equal DS::DSNot, invariant.formula.class
      assert_equal false, invariant.formula.subformula.bool_value
    end
  end

  def test_invariant__and_or
    parser = ADSL::ADSLParser.new
    operators = {
      "and" => DS::DSAnd, 
      "or" => DS::DSOr 
    }
    operators.each do |word, type|
      spec = parser.parse <<-ADSL
        invariant true #{word} false
      ADSL
      invariant = spec.invariants.first
      assert_equal type, invariant.formula.class
      assert_equal [true, false], invariant.formula.subformulae.map{ |a| a.bool_value}
      
      spec = parser.parse <<-ADSL
        invariant true #{word} false #{word} true
      ADSL
      invariant = spec.invariants.first
      assert_equal type, invariant.formula.class
      assert_equal [true, false, true], invariant.formula.subformulae.map{ |a| a.bool_value}
    end
  end

  def test_invariant__operator_precedence_and_associativity
    parser = ADSL::ADSLParser.new
    operators = {
      "and" => DS::DSAnd, 
      "or" => DS::DSOr 
    }
    operators.each do |word, type|
      spec = parser.parse <<-ADSL
        invariant not true #{word} false
      ADSL
      invariant = spec.invariants.first
      assert_equal type, invariant.formula.class
      assert_equal DS::DSNot, invariant.formula.subformulae.first.class
      assert_equal false, invariant.formula.subformulae.second.bool_value
    end
    operators.each do |word, type|
      spec = parser.parse <<-ADSL
        invariant not (true #{word} false)
      ADSL
      invariant = spec.invariants.first
      assert_equal DS::DSNot, invariant.formula.class
      assert_equal type, invariant.formula.subformula.class
    end
    spec = parser.parse <<-ADSL
      invariant true and !false or true
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSOr, invariant.formula.class
    assert_equal true, invariant.formula.subformulae.second.bool_value
    assert_equal DS::DSAnd, invariant.formula.subformulae.first.class
    assert_equal true, invariant.formula.subformulae.first.subformulae.first.bool_value
    assert_equal DS::DSNot, invariant.formula.subformulae.first.subformulae.second.class
  end

  def test_invariant__equal
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-ADSL
      class Class {}
      invariant exists(Class o1, Class o2: o1 == o2)
    ADSL
    f = spec.invariants.first.formula.subformula
    assert_equal DS::DSEqual, f.class
    assert_equal ['o1', 'o2'], f.objsets.map { |v| v.name }

    spec = parser.parse <<-ADSL
      class Class {}
      invariant exists(Class o1, Class o2: equal(o1, o2))
    ADSL
    f = spec.invariants.first.formula.subformula
    assert_equal DS::DSEqual, f.class
    assert_equal ['o1', 'o2'], f.objsets.map { |v| v.name }

    spec = parser.parse <<-ADSL
      class Class {}
      invariant exists(Class o1, Class o2: equal(o1, o2, o1, o1))
    ADSL
    f = spec.invariants.first.formula.subformula
    assert_equal DS::DSEqual, f.class
    assert_equal ['o1', 'o2', 'o1', 'o1'], f.objsets.map { |v| v.name }

    assert_nothing_raised ADSL::ADSLError do
      parser.parse <<-ADSL
        class Class {}
        class Child extends Class {}
        invariant allof(Class) == allof(Child)
      ADSL
    end
    assert_raise ADSL::ADSLError do
      parser.parse <<-ADSL
        class Class1 {}
        class Class2 {}
        invariant allof(Class1) == allof(Child2)
      ADSL
    end
    assert_raise ADSL::ADSLError do
      parser.parse <<-ADSL
        class Parent {}
        class Class1 extends Parent {}
        class Class2 extends Parent {}
        invariant equal(allof(Parent), allof(Class1), allof(Child2))
      ADSL
    end
  end

  def test_invariant__not_equal
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-ADSL
      class Class {}
      invariant exists(Class o1, Class o2: o1 != o2)
    ADSL
    f = spec.invariants.first.formula.subformula
    assert_equal DS::DSNot, f.class
    assert_equal DS::DSEqual, f.subformula.class
    assert_equal ['o1', 'o2'], f.subformula.objsets.map { |v| v.name }
  end
  
  def test_invariant__equiv
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-ADSL
      class Class {}
      invariant true <=> false
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSEquiv, invariant.formula.class
    assert_equal [true, false], invariant.formula.subformulae.map{ |f| f.bool_value }
    
    spec = parser.parse <<-ADSL
      class Class {}
      invariant equiv(true, false)
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSEquiv, invariant.formula.class
    assert_equal [true, false], invariant.formula.subformulae.map{ |f| f.bool_value }
    
    spec = parser.parse <<-ADSL
      class Class {}
      invariant equiv(true, false, true, true)
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSEquiv, invariant.formula.class
    assert_equal [true, false, true, true], invariant.formula.subformulae.map{ |f| f.bool_value }
  end

  def test_invariant__implies
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-ADSL
      class Class {}
      invariant true => false
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSImplies, invariant.formula.class
    assert_equal true,  invariant.formula.subformula1.bool_value
    assert_equal false, invariant.formula.subformula2.bool_value
    
    spec = parser.parse <<-ADSL
      class Class {}
      invariant false <= true
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSImplies, invariant.formula.class
    assert_equal true,  invariant.formula.subformula1.bool_value
    assert_equal false, invariant.formula.subformula2.bool_value
    
    spec = parser.parse <<-ADSL
      class Class {}
      invariant implies(true, false)
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSImplies, invariant.formula.class
    assert_equal true,  invariant.formula.subformula1.bool_value
    assert_equal false, invariant.formula.subformula2.bool_value
  end
  
  def test_invariant__empty
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-ADSL
      class Class {}
      invariant empty(allof(Class))
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSEmpty, invariant.formula.class
    assert_equal DS::DSAllOf, invariant.formula.objset.class
  end

  def test_invariant__in
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-ADSL
      class Class {}
      invariant allof(Class) in allof(Class)
    ADSL
    invariant = spec.invariants.first
    assert_equal DS::DSIn, invariant.formula.class
    assert_equal DS::DSAllOf, invariant.formula.objset1.class
    assert_equal DS::DSAllOf, invariant.formula.objset2.class

    assert_raise ADSL::ADSLError do
      parser.parse <<-ADSL
        class Class1 {}
        class Class2 {}
        invariant allof(Class1) in allof(Class2)
      ADSL
    end
    assert_raise ADSL::ADSLError do
      parser.parse <<-ADSL
        class Super {}
        class Sub extends Super {}
        invariant allof(Super) in allof(Sub)
      ADSL
    end
    assert_nothing_raised ADSL::ADSLError do
      parser.parse <<-ADSL
        class Super {}
        class Sub extends Super {}
        invariant allof(Sub) in allof(Super)
      ADSL
    end
  end

  def test_invariant__variable_scope
    parser = ADSL::ADSLParser.new
    spec = parser.parse <<-ADSL
      class Class {}
      invariant exists(Class o)
      invariant exists(Class o)
      invariant exists(Class o)
      invariant exists(Class o)
    ADSL
  end
end
