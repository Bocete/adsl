require 'test/unit'
require 'util/util'
require 'util/test_helper'

class UtilTest < Test::Unit::TestCase

  def setup
    assert_false class_defined? :Foo, :Foo2
  end

  def teardown
    unload_class :Foo, :Foo2
  end

  def test_module__lookup_const
    assert_equal Module, self.class.lookup_const('Module')
    assert_equal Module, self.class.lookup_const(:Module)
    assert_equal Object, self.class.lookup_const('::Object')
    assert_equal Test::Unit, self.class.lookup_const('Test::Unit')
    assert_equal Test::Unit::TestCase, self.class.lookup_const('Test::Unit::TestCase')
    assert_equal Test::Unit::TestCase, Test::Unit.lookup_const('TestCase')
  end

  def test_module__lookup_or_create_module
    assert_equal Module, self.class.lookup_or_create_module('Module')
    assert_equal Module, self.class.lookup_or_create_module('::Module')
    assert_equal Module, self.class.lookup_or_create_module(:Module)
    foo = self.class.lookup_or_create_module(:Foo)
    assert_equal Module, foo.class
    assert_equal Foo, foo

    assert_equal Test::Unit, self.class.lookup_or_create_module('Test::Unit')
    new_deep = self.class.lookup_or_create_module('Test::Unit::NewDeep')
    assert_equal Module, new_deep.class
    assert_equal Test::Unit::NewDeep, new_deep
  end
  
  def test_module__lookup_or_create_class
    assert_equal Object, self.class.lookup_or_create_class('Object', nil)
    assert_equal Object, self.class.lookup_or_create_class('::Object', nil)
    assert_equal Object, self.class.lookup_or_create_class(:Object, nil)
    foo = self.class.lookup_or_create_class(:Foo, Object)
    assert_equal Class, foo.class
    assert_equal Foo, foo
    assert_equal Object, foo.superclass

    assert_equal Test::Unit::TestCase, self.class.lookup_or_create_class('Test::Unit::TestCase', Test::Unit::TestCase.superclass)
    new_deep = self.class.lookup_or_create_class('Test::Unit::NewDeep', String)
    assert_equal Class, new_deep.class
    assert_equal Test::Unit::NewDeep, new_deep
    assert_equal String, new_deep.superclass
  ensure
    unload_class 'Test::Unit::NewDeep'
  end

  def test_container_for__blank
    assert_raise ArgumentError do
      eval <<-ruby
        class Foo
          container_for
        end
      ruby
    end
  end

  def test_container_for__does_list
    eval <<-ruby
      class Foo
        container_for :field
      end
    ruby

    kme = Foo.new
    assert_nil kme.field

    kme = Foo.new :field => :asd
    assert_equal :asd, kme.field
  end

  def test_container_for__nonoverwriting
    eval <<-ruby
      class Foo
        container_for :field
      end

      class Foo
        container_for :field2
      end
    ruby

    assert_nothing_raised do
      Foo.new
      Foo.new :field => 4
      Foo.new :field2 => 5
      a = Foo.new :field => 1, :field2 => 2
      assert_equal 1, a.field
      assert_equal 2, a.field2
    end
  end

  def test_container_for__container_for_fields_and_inheritance
    eval <<-ruby
      class Foo
      end
    ruby
    
    assert_raise do
      Foo.container_for_fields
    end
    
    eval <<-ruby
      class Foo
        container_for :field
      end

      class Foo2 < Foo
      end
    ruby

    assert_raise do
      Class.container_for_fields
    end

    assert_equal [:field], Foo.container_for_fields.to_a
    assert_equal [:field], Foo2.container_for_fields.to_a
    
    eval <<-ruby
      class Foo
        container_for :field2
      end
    ruby
    assert_equal [:field, :field2], Foo.container_for_fields.to_a.sort_by{ |a| a.to_s }
    assert_equal [:field, :field2], Foo2.container_for_fields.to_a.sort_by{ |a| a.to_s }

    eval <<-ruby
      class Foo2 < Foo
        container_for :field3
      end
    ruby
    assert_equal [:field, :field2], Foo.container_for_fields.to_a.sort_by{ |a| a.to_s }
    assert_equal [:field, :field2, :field3], Foo2.container_for_fields.to_a.sort_by{ |a| a.to_s }
  end

  def test_container_for__doesnt_list
    eval <<-ruby
      class Foo
        container_for :field
      end
    ruby

    assert_raise ArgumentError do
      Foo.new :unknown_field => :value
    end
  end

  def test_container_for__block
    eval <<-ruby
      class Foo
        container_for :field do
          raise 'inside block'
        end
      end
    ruby

    assert_raise RuntimeError, 'Inside block' do
      Foo.new
    end
  end

  def test_container_for__block_allows_extra_args
    eval <<-ruby
      class Foo
        container_for :field do; end
      end
    ruby

    Foo.new :unmentioned_field => :whatever
  end

  def test_container_for__recursively_gather
    eval <<-ruby
      class Foo
        container_for :field1, :field2
        attr_accessor :content
      end
    ruby

    assert_equal [:field1, :field2], Foo.container_for_fields.to_a.sort_by{ |a| a.to_s }
    assert Foo.method_defined?(:recursively_gather)
    assert_equal Set[], Foo.new.recursively_gather(:field1)
    assert_equal Set[:a], Foo.new(:field1 => :a).recursively_gather(:field1)
    
    foo = Foo.new
    foo.content = :kme
    foo.field1 = Foo.new :field1 => :kme
    foo.field1.content = :kme2
    foo.field2 = Foo.new :field1 => Foo.new
    foo.field2.content = :kme
    assert_equal Set[:kme, :kme2], foo.recursively_gather(:content)

    newchild = Foo.new
    newchild.content = :asd
    foo.field1 = [newchild, foo.field1]
    assert_equal Set[:kme, :kme2, :asd], foo.recursively_gather(:content)
  end

  def test_container_for__recursively_gather_recursively_safe
    eval <<-ruby
      class Foo
        container_for :field
        attr_accessor :content
      end
    ruby

    foo = Foo.new
    foo.field = foo
    foo.content = :a
    assert_equal Set[:a], foo.recursively_gather(:content)
  end

  def test_process_race__1_process
    stdout = process_race "echo 'blah'"
    assert_equal 'blah', stdout.strip
  end
  
  def test_process_race__2_processes
    time = Time.now
    stdout = process_race "echo 'blah'", "sleep 20; echo 'blah2'"
    assert (Time.now - time) < 1
    assert_equal 'blah', stdout.strip
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
    assert_equal UtilTest, Foo.parent_module
    assert_equal UtilTest::Foo, Foo::Foo2.parent_module
  end
end
