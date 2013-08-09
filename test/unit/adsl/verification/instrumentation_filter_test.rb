require 'test/unit'
require 'adsl/verification/instrumentation_filter'

module ADSL::Verification
  class InstrumentationFilterTest < Test::Unit::TestCase

    def asd; end
    def kme; end

    def test_applies_to__method_name
      filter = InstrumentationFilter.new :method_name => :asd
      assert filter.applies_to?(self, :asd)

      filter = InstrumentationFilter.new :method_name => 'asd'
      assert filter.applies_to?(self, :asd)
      
      filter = InstrumentationFilter.new :method_name => /\w+/
      assert filter.applies_to?(self, :asd)
      
      filter = InstrumentationFilter.new :method_name => :asd
      assert_false filter.applies_to?('asd', :length)
    end
    
    def test_applies_to__owner
      filter = InstrumentationFilter.new :method_owner => InstrumentationFilterTest
      assert filter.applies_to?(self, :asd)

      filter = InstrumentationFilter.new :method_owner => Test::Unit::TestCase
      assert_false filter.applies_to?(self, :asd)
    end
    
    def test_applies_to__method_name_and_owner
      filter = InstrumentationFilter.new :method_name => 'asd', :method_owner => InstrumentationFilterTest
      assert filter.applies_to?(self, :asd)
      assert_false filter.applies_to?(self, :kme)
    end

  end
end
