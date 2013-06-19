require 'test/unit'
require 'extract/instrumenter'
require 'pp'
require 'util/test_helper'

class InstrumenterTest < Test::Unit::TestCase
  class Foo
    def blah
      [1, 2, 3]
    end

    def call_blah
      blah
    end

    def repeat_blah(arg)
      arg.times.map do
        blah
      end.to_a
    end

    def empty_method
    end

    Foo.instance_methods(false).each do |method_name|
      alias_method "old_#{method_name}", method_name unless method_name =~ /^old_.*$/
    end
  end

  def setup
    assert_equal [1, 2, 3], Foo.new.blah
    assert_equal nil, Foo.new.empty_method
    assert_equal [1, 2, 3], Foo.new.call_blah
    assert_equal [[1, 2, 3], [1, 2, 3]], Foo.new.repeat_blah(2)
  end

  def teardown
    Foo.class_eval do
      Foo.instance_methods(false).each do |method_name|
        alias_method method_name, "old_#{method_name}" unless method_name =~ /^old_.*$/
      end
    end
  end
  
  def test_execute_instrumented__blank
    instrumenter = Extract::Instrumenter.new
    assert_equal [1, 2, 3], instrumenter.execute_instrumented(Foo.new, :blah)
  end
  
  def test_execute_instrumented__plain_replace
    instrumenter = Extract::Instrumenter.new
    
    instrumenter.replace :lit do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal [2, 4, 6], instrumenter.execute_instrumented(Foo.new, :blah)
  end

  def test_execute_instrumented__instrumentation_does_not_wreck_empty_methods
    instrumenter = Extract::Instrumenter.new
    assert_equal nil, instrumenter.execute_instrumented(Foo.new, :empty_method)
  end

  def test_execute_instrumented__calls_work
    instrumenter = Extract::Instrumenter.new
    assert_equal [1, 2, 3], instrumenter.execute_instrumented(Foo.new, :call_blah) 
  end

  def test_execute_instrumented__instrumentation_propagates_through_calls
    instrumenter = Extract::Instrumenter.new

    instrumenter.replace :lit do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal [2, 4, 6], instrumenter.execute_instrumented(Foo.new, :call_blah) 
  end
  
  def test_execute_instrumented__instrumentation_happens_once
    instrumenter = Extract::Instrumenter.new
    
    instrumenter.replace :lit do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal [[2, 4, 6]], instrumenter.execute_instrumented(Foo.new, :repeat_blah, 1)
    assert_equal [[2, 4, 6], [2, 4, 6]], instrumenter.execute_instrumented(Foo.new, :repeat_blah, 2)
    assert_equal [2, 4, 6], instrumenter.execute_instrumented(Foo.new, :blah)
  end
end
