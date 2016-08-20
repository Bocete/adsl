require 'adsl/util/test_helper'
require 'adsl/extract/instrumenter'

class ADSL::Extract::InstrumenterTest < ActiveSupport::TestCase
  class Foo
  end

  def setup
    Foo.class_exec do
      def blah
        [1, 2, 3]
      end
      
      def preinstrumented_blah
        ::ADSL::Extract::Instrumenter.instrumented
        blah
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

      def self.blah
        [3, 2, 1]
      end

      def self.call_blah
        self.blah
      end
    end

    assert_equal [1, 2, 3], Foo.new.blah
    assert_equal nil, Foo.new.empty_method
    assert_equal [1, 2, 3], Foo.new.call_blah
    assert_equal [[1, 2, 3], [1, 2, 3]], Foo.new.repeat_blah(2)
  end

  def teardown
  end
  
  def test_execute_instrumented__blank
    instrumenter = ADSL::Extract::Instrumenter.new
    assert_equal [1, 2, 3], instrumenter.execute_instrumented(Foo.new, :blah)
  end
  
  def test_execute_instrumented__plain_replace
    instrumenter = ADSL::Extract::Instrumenter.new
    
    instrumenter.replace :lit do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal [2, 4, 6], instrumenter.execute_instrumented(Foo.new, :blah)
  end

  def test_execute_instrumented__instrumentation_does_not_wreck_empty_methods
    instrumenter = ADSL::Extract::Instrumenter.new
    assert_equal nil, instrumenter.execute_instrumented(Foo.new, :empty_method)
  end

  def test_execute_instrumented__calls_work
    instrumenter = ADSL::Extract::Instrumenter.new
    assert_equal [1, 2, 3], instrumenter.execute_instrumented(Foo.new, :call_blah) 
  end

  def test_execute_instrumented__instrumentation_propagates_through_calls
    instrumenter = ADSL::Extract::Instrumenter.new

    instrumenter.replace :lit do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal [2, 4, 6], instrumenter.execute_instrumented(Foo.new, :call_blah) 
  end
  
  def test_execute_instrumented__instrumentation_happens_once
    instrumenter = ADSL::Extract::Instrumenter.new
    
    instrumenter.replace :lit do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal [[2, 4, 6]], instrumenter.execute_instrumented(Foo.new, :repeat_blah, 1)
    assert_equal [[2, 4, 6], [2, 4, 6]], instrumenter.execute_instrumented(Foo.new, :repeat_blah, 2)
    assert_equal [2, 4, 6], instrumenter.execute_instrumented(Foo.new, :blah)
  end
  
  def test_execute_instrumented__instrumentation_propagates_through_class_level_calls
    instrumenter = ADSL::Extract::Instrumenter.new

    instrumenter.replace :lit do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal [6, 4, 2], instrumenter.execute_instrumented(Foo, :call_blah) 
  end

  def test_execute_instrumented__instrumentation_can_be_skipped
    instrumenter = ADSL::Extract::Instrumenter.new

    instrumenter.replace :lit do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal [1, 2, 3], instrumenter.execute_instrumented(Foo.new, :preinstrumented_blah)
  end
end
