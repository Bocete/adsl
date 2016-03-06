require 'adsl/util/test_helper'
require 'adsl/util/container'

class ADSL::Util::GeneralTest < ActiveSupport::TestCase

  def setup
    assert_false class_defined? :Foo, :Foo2
  end

  def teardown
    unload_class :Foo, :Foo2
  end

  def test_blank
    eval <<-ruby
      class Foo
        container_for
      end
    ruby

    assert Foo.container_for_fields.empty?
  end

  def test_does_list
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

  def test_nonoverwriting
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

  def test_container_for_fields_and_inheritance
    eval <<-ruby
      class Foo
      end
    ruby
    
    assert_raises NoMethodError do
      Foo.container_for_fields
    end
    
    eval <<-ruby
      class Foo
        container_for :field
      end

      class Foo2 < Foo
      end
    ruby

    assert_raises NoMethodError do
      Class.container_for_fields
    end

    assert_equal [:field], Foo.container_for_fields.to_a
    assert_equal [:field], Foo2.container_for_fields.to_a
    
    eval <<-ruby
      class Foo
        container_for :field2
      end
    ruby
    assert_equal [:field, :field2], Foo.container_for_fields.to_a.sort_by(&:to_s)
    assert_equal [:field, :field2], Foo2.container_for_fields.to_a.sort_by(&:to_s)

    eval <<-ruby
      class Foo2 < Foo
        container_for :field3
      end
    ruby
    assert_equal [:field, :field2], Foo.container_for_fields.to_a.sort_by(&:to_s)
    assert_equal [:field, :field2, :field3], Foo2.container_for_fields.to_a.sort_by(&:to_s)
  end

  def test_doesnt_list
    eval <<-ruby
      class Foo
        container_for :field
      end
    ruby

    assert_raises ArgumentError do
      Foo.new :unknown_field => :value
    end
  end

  def test_recursively_gather
    eval <<-ruby
      class Foo
        container_for :field1, :field2
        attr_accessor :content
      end
    ruby

    assert_equal [:field1, :field2], Foo.container_for_fields.to_a.sort_by(&:to_s)
    assert Foo.method_defined?(:recursively_gather)
    assert_equal [], Foo.new.recursively_gather{ |c| c.field1 if c.is_a? Foo }
    assert_equal [:a], Foo.new(:field1 => :a).recursively_gather{ |c| c.field1 if c.is_a? Foo }
    
    foo = Foo.new
    foo.content = :kme
    foo.field1 = Foo.new :field1 => :kme
    foo.field1.content = :kme2
    foo.field2 = Foo.new :field1 => Foo.new
    foo.field2.content = :kme
    assert_equal [:kme, :kme, :kme2], foo.recursively_gather{ |c| c.content if c.is_a? Foo }

    newchild = Foo.new
    newchild.content = :asd
    foo.field1 = [newchild, foo.field1]
    assert_equal [:kme, :kme, :kme2, :asd], foo.recursively_gather{ |c| c.content if c.is_a? Foo }
  end

  def test_recursively_gather_recursively_safe
    eval <<-ruby
      class Foo
        container_for :field
        attr_accessor :content
      end
    ruby

    foo = Foo.new
    foo.field = foo
    foo.content = :a
    assert_equal [:a], foo.recursively_gather{ |c| c.content if c.is_a? Foo }
  end

  def test_recursively_comparable__appears
    eval <<-ruby
      class Foo
      end
    ruby

    assert_raises NoMethodError do
      Foo.recursively_comparable
    end
    
    eval <<-ruby
      class Foo
        container_for :field, :array
      end
    ruby

    Foo.recursively_comparable
  end

  def test_recursively_comparable__basic_types
    eval <<-ruby
      class Foo
        container_for :field1, :field2
        recursively_comparable
      end
    ruby

    assert_equal     Foo.new(:field1 => 1, :field2 => 2), Foo.new(:field1 => 1, :field2 => 2)
    assert_not_equal Foo.new(:field1 => 1, :field2 => 2), Foo.new()
    assert_not_equal Foo.new(:field1 => 1, :field2 => 2), Foo.new(:field1 => 1, :field2 => 3)
  end

  def test_recursively_comparable__arrays
    eval <<-ruby
      class Foo
        container_for :field, :array
        recursively_comparable
      end
    ruby

    assert_equal     Foo.new(:array => []), Foo.new(:array => [])
    assert_equal     Foo.new(:array => [:a, :b, :c]), Foo.new(:array => [:a, :b, :c])
    assert_not_equal Foo.new(:array => [:a, :b, :c]), Foo.new(:array => [:a, :b, :c, :d])
    assert_not_equal Foo.new(:array => [:a, :b, :c]), Foo.new()
    assert_not_equal Foo.new(:array => [:a, :b, :c]), Foo.new(:array => [:a, :b, :c], :field => :p)
  end

  def test_recursively_compare__dup
    eval <<-ruby
      class Foo
        container_for :field, :array
        recursively_comparable
      end
    ruby
    foo = Foo.new :field => :p, :array => [1, 2, 3]

    foo2 = foo.dup
    assert_equal foo, foo2
    foo2.field = :d
    assert_not_equal foo, foo2

    foo2 = foo.dup
    assert_equal foo, foo2
    foo2.array << 4
    assert_not_equal foo, foo2
  end

  def test_recursively_select
    eval <<-ruby
      class Foo
        container_for :elem, :array
      end
      class Foo2
        container_for :elem, :array
      end
    ruby

    foo = Foo.new :elem => :a, :array => [:b, :c]
    assert_equal [:a, :b, :c], foo.recursively_select{ true }
    assert_equal [],           foo.recursively_select{ false }
    assert_equal [],           foo.recursively_select{ nil }

    foo2 = Foo2.new :elem => foo, :array => [1, 2]

    assert_equal [foo, :a, :b, :c, 1, 2], foo2.recursively_select{ true }
    assert_equal [1, 2],                  foo2.recursively_select{ |r| !r.is_a? Foo }
    assert_equal [],                      foo2.recursively_select{ nil }
  end
end
