
require 'test/unit'
require 'extract/meta'
require 'pp'
require 'util/test_helper'

class MetaTest < Test::Unit::TestCase
  def setup
    assert_false class_defined? :Foo, :Bar
  end

  def teardown
    unload_class :Foo, :Bar
  end

  def test_class__inheritance_chain
    assert_equal [BasicObject, Object, String], String.inheritance_chain
  end

  def test_object__replace_method__crashes_when_no_method_exists
    eval <<-ruby
      class Foo; end
    ruby
    assert_raise do
      Foo.new.replace_method :a, "def a; end"
    end
  end
  
  def test_object__replace_method__simple
    eval <<-ruby
      class Foo
        def a; :old; end
      end
    ruby
    assert_equal :old, Foo.new.a

    Foo.new.replace_method :a, "def a; :new; end"

    assert_equal :new, Foo.new.a
  end

  def test_object__replace_method__eigenclass
    eval <<-ruby
      class Foo
        def a; :old; end
      end
    ruby

    foo = Foo.new
    def foo.a; :overridden; end

    assert_equal :old, Foo.new.a
    assert_equal :overridden, foo.a

    foo.replace_method :a, "def a; :new; end"

    assert_equal :old, Foo.new.a
    assert_equal :new, foo.a
  end
  
  def test_object__replace_method__leaves_super_class_alone_if_overridden
    eval <<-ruby
      class Foo
        def a; :old; end
      end
      class Bar < Foo
        def a; :old; end
      end
    ruby
    assert_equal :old, Foo.new.a
    assert_equal :old, Bar.new.a

    Bar.new.replace_method :a, "def a; :new; end"

    assert_equal :old, Foo.new.a
    assert_equal :new, Bar.new.a
  end
  
  def test_object__replace_method__targets_superclass
    eval <<-ruby
      class Foo
        def a; :old; end
      end
      class Bar < Foo
      end
    ruby
    assert_equal :old, Foo.new.a
    assert_equal :old, Bar.new.a

    Bar.new.replace_method :a, "def a; :new; end"

    assert_equal :new, Foo.new.a
    assert_equal :new, Bar.new.a
  end
  
  def test_object__replace_method__targets_module
    eval <<-ruby
      module Foo
        def a; :old; end
      end
      class Bar
        include Foo
      end
    ruby
    assert_equal :old, Bar.new.a

    Bar.new.replace_method :a, "def a; :new; end"

    assert_equal :new, Bar.new.a
  end

end
