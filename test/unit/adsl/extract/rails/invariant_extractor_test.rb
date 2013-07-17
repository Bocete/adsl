require 'test/unit'
require 'adsl/util/test_helper'
require 'adsl/extract/rails/invariant_extractor'
require 'adsl/extract/rails/rails_instrumentation_test_case'

module ADSL::Extract::Rails
  class InvariantExtractorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
    def test_load_in_context
      invariant_string = <<-invariants
        invariant "blah", true

        invariant("second", forall do |asd|
          asd.empty?
        end)

        invariant true
      invariants
      
      ie = InvariantExtractor.new
      ie.extract invariant_string
      assert_equal 3, ie.invariants.length

      assert_equal 'blah',   ie.invariants[0].description
      assert_equal true,     ie.invariants[0].formula.bool_value

      assert_equal 'second', ie.invariants[1].description
      assert_equal 'asd',    ie.invariants[1].formula.vars[0][0].text
      
      assert_equal nil,      ie.invariants[2].description
      assert_equal true,     ie.invariants[2].formula.bool_value
    end
  end
end
