require 'adsl/util/test_helper'
require 'adsl/util/general'

class ADSL::Util::GeneralTest < ActiveSupport::TestCase

  def setup
    assert_false class_defined? :Foo, :Foo2
  end

  def teardown
    unload_class :Foo, :Foo2, 'MiniTest::Unit::NewDeep'
  end

  def test_module__lookup_const
    assert_equal Module, self.class.lookup_const('Module')
    assert_equal Module, self.class.lookup_const(:Module)
    assert_equal Object, self.class.lookup_const('::Object')
    assert_equal MiniTest::Unit, self.class.lookup_const('MiniTest::Unit')
    assert_equal ActiveSupport::TestCase, self.class.lookup_const('ActiveSupport::TestCase')
  end

  def test_module__lookup_or_create_module
    assert_equal Module, self.class.lookup_or_create_module('Module')
    assert_equal Module, self.class.lookup_or_create_module('::Module')
    assert_equal Module, self.class.lookup_or_create_module(:Module)
    foo = self.class.lookup_or_create_module(:Foo)
    assert_equal Module, foo.class
    assert_equal Foo, foo

    assert_equal MiniTest::Unit, self.class.lookup_or_create_module('MiniTest::Unit')
    new_deep = self.class.lookup_or_create_module('MiniTest::Unit::NewDeep')
    assert_equal Module, new_deep.class
    assert_equal MiniTest::Unit::NewDeep, new_deep
  end
  
  def test_module__lookup_or_create_class
    assert_equal Object, self.class.lookup_or_create_class('Object', nil)
    assert_equal Object, self.class.lookup_or_create_class('::Object', nil)
    assert_equal Object, self.class.lookup_or_create_class(:Object, nil)
    foo = self.class.lookup_or_create_class(:Foo, Object)
    assert_equal Class, foo.class
    assert_equal Foo, foo
    assert_equal Object, foo.superclass

    assert_equal ActiveSupport::TestCase, self.class.lookup_or_create_class('ActiveSupport::TestCase', ActiveSupport::TestCase.superclass)
    new_deep = self.class.lookup_or_create_class('MiniTest::Unit::NewDeep', String)
    assert_equal Class, new_deep.class
    assert_equal MiniTest::Unit::NewDeep, new_deep
    assert_equal String, new_deep.superclass
  ensure
    unload_class 'MiniTest::Unit::NewDeep'
  end

  def test_string__increment_suffix
    assert_equal 'asd_2', 'asd'.increment_suffix
    assert_equal 'asd_3', 'asd_2'.increment_suffix
    assert_equal 'asd_123', 'asd_122'.increment_suffix
    assert_equal 'a1s2_d4_2', 'a1s2_d4'.increment_suffix
  end

  def test_array__worklist_each__plain
    worklist = [3, 2, 1, 0]
    looking_for = 0
    worklist.worklist_each do |task|
      if task == looking_for
        looking_for += 1
        next
      else
        next task
      end
    end
    assert worklist.empty?
    assert_equal 4, looking_for
  end
  
  def test_array__worklist_each__stops_on_no_change
    worklist = [3, 2, 5, 19, 1, 0]
    looking_for = 0
    worklist.worklist_each do |task|
      if task == looking_for
        looking_for += 1
        next
      else
        next task
      end
    end
    assert_equal 4, looking_for
  end

  def test_module__parent_module
    eval <<-ruby
      module Foo
        class Foo2
        end
      end
    ruby

    assert_equal Object, String.parent_module
    assert_equal ADSL::Util::GeneralTest, Foo.parent_module
    assert_equal ADSL::Util::GeneralTest::Foo, Foo::Foo2.parent_module
  end

  def test_array__split_simple
    array = [-1, 3, 12, -5, 20, 0, 45]

    accepted, rejected = array.select_reject{ |i| i > 0 }
    assert_equal [3, 12, 20, 45], accepted
    assert_equal [-1, -5, 0], rejected
  end

  def test_array__split_cornercases
    accepted, rejected = [1, 2, 3, 4, 5].select_reject{ |i| i > 0 }
    assert_equal [1, 2, 3, 4, 5], accepted
    assert_equal [], rejected
   
    accepted, rejected = [1, 2, 3, 4, 5].select_reject{ |i| i < 0 }
    assert_equal [], accepted
    assert_equal [1, 2, 3, 4, 5], rejected

    accepted, rejected = [].select_reject{ |i| i < 0 }
    assert_equal [], accepted
    assert_equal [], rejected
  end

  def test_enumerable__find_one
    assert [1, 2, 3].respond_to?(:find_one)
    assert_raises ArgumentError do
      [1, 2, 3, 4, 5].find_one{ |c| c == 7 }
    end
    assert_raises ArgumentError do
      [1, 2, 1, 2, 1].find_one{ |c| c == 1 }
    end
    assert_equal 4, [1, 3, 4, 5, 7].find_one{ |c| c.even? }
    assert_equal 4, Set[1, 3, 4, 5, 7].find_one{ |c| c.even? }
  end

  def test_range__empty
    assert_false (1..2).empty?
    assert_false (1..1).empty?
    assert (1..0).empty?
    assert (1...1).empty?
  end

  def test_range__intersect
    assert_equal (2..3), (1..3).intersect(2..4)
    assert_equal (2..3), (2..3).intersect(2..3)
    assert_equal (2..3), (2..4).intersect(1..3)
    assert_equal (2..3), (2..3).intersect(0..20)
    assert (2..3).intersect(4..6).empty?
    assert (0..5).intersect(1...1).empty?
  end

  def test_range__inject_on_intersection
    assert_equal (2..3), [1..6, 2..12, 0..3].inject(:intersect)
    assert [1..6, 2..3, 0...0].inject(:intersect).empty?
  end

  def test_array__each_index
    assert [].respond_to? :each_index
    assert [].respond_to? :each_index_with_elem
    assert [].respond_to? :each_index_without_elem

    list = [1, 2, 3].each_index
    [1, 2, 3].each do |e|
      assert_equal e, list.next + 1
    end

    a = 1
    [1, 2, 3].each_index do |i|
      assert_equal a, i + 1
      a += 1
    end

    [3, 4, 5].each_index do |elem, i|
      assert_equal elem, i + 3
    end
  end

  def test_array__map_index
    assert [].respond_to? :map_index

    result = [1, 2, 3].map_index do |elem, i|
      assert_equal elem, i+1
      'a' * elem
    end
    assert_equal ['a', 'aa', 'aaa'], result 
  end

  def test_array__try_map
    a = [13, 35, [], "kme", nil]
    assert_equal [13, 35, 0, 3, nil], a.try_map(:length)
    assert_equal [13, 35, [], "kme", nil], a
  end

  def test_array__try_map!
    a = [13, 35, [], "kme", nil]
    assert_equal [13, 35, 0, 3, nil], a.try_map!(:length)
    assert_equal [13, 35, 0, 3, nil], a
  end
  
  def test_string__resolve_params_distinct_identifiers
    a = "asd(${1}, ${2})"
    assert_equal "asd(a, b)", a.resolve_params(:a, :b)
    assert_raises ArgumentError do
      a.resolve_params(:s)
    end
    assert_equal "asd(s, k)", a.resolve_params(:s, :k, :r)
  end
  
  def test_string__resolve_params_repeating_identifiers
    a = "asd(${1}, ${2}): ${1}"
    assert_equal "asd(a, b): a", a.resolve_params(:a, :b)
    assert_raises ArgumentError do
      a.resolve_params(:s)
    end
    assert_equal "asd(s, k): s", a.resolve_params(:s, :k, :r)
  end

  def test_array_deep_dup
    a = ['a', 1, 2, true, nil]
    assert_equal a, a.deep_dup
    clone = a.deep_dup
    clone[2] = 123
    assert_not_equal a, clone

    a = [[[1]]]
    clone = a.deep_dup
    clone[0][0][0] = 4
    assert_not_equal a, clone
  end

  def inc_a(a)
    ensure_once { a + 1 }
  end
  def test_ensure_once_simple
    a = 0
    ensure_once { a = 1 }
    assert_equal 1, a

    ensure_once(:key) { a = a + 1 }
    ensure_once(:key) { a = a + 1 }
    assert_equal 2, a

    ensure_once { a = a + 1 }
    ensure_once { a = a + 1 }
    assert_equal 4, a

    a = inc_a a
    a = inc_a a
    assert_equal 5, a
  end

  def test_string__without_leading_whitespace
    assert_equal "asd", "asd".without_leading_whitespace
    assert_equal "asd", "           asd".without_leading_whitespace
    assert_equal "asd  ", "  asd  ".without_leading_whitespace

    assert_equal "asd\nasd", "  asd\n  asd".without_leading_whitespace
    assert_equal "asd\n  asd", "  asd\n    asd".without_leading_whitespace
    assert_equal "  asd\nasd", "    asd\n  asd".without_leading_whitespace
    assert_equal "asd\n\nasd", "  asd\n\n  asd".without_leading_whitespace
  end
end
