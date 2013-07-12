require 'test/unit'
require 'adsl/util/test_helper'
require 'adsl/extract/rails/invariant_extractor'
require 'adsl/extract/rails/rails_instrumentation_test_case'

module ADSL::Extract::Rails
  class InvariantExtractorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
    def test_load_in_context
      file_content = <<-invariants
        invariant "blah"
        self.true

        invariant "second"
        forall do |asd|
          asd.empty?
        end

        self.true
      invariants
      
      ie = InvariantExtractor.new
      in_temp_file file_content do |path|
        ie.load_in_context path
      end
      assert_equal 3, ie.invariants.length

      assert_equal 'blah',   ie.invariants[0].description
      assert_equal true,     ie.invariants[0].adsl_ast.bool_value

      assert_equal 'second', ie.invariants[1].description
      assert_equal 'asd',    ie.invariants[1].adsl_ast.vars[0][0].text
      
      assert_equal nil,      ie.invariants[2].description
      assert_equal true,     ie.invariants[2].adsl_ast.bool_value
    end
  end
end
