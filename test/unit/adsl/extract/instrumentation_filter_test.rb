require 'adsl/util/test_helper'
require 'adsl/extract/instrumentation_filter'

class ADSL::Extract::InstrumentationFilterTest < ActiveSupport::TestCase
  include ADSL::Extract

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

    filter = InstrumentationFilter.new :method_owner => ActiveSupport::TestCase
    assert_false filter.applies_to?(self, :asd)
  end
  
  def test_applies_to__method_name_and_owner
    filter = InstrumentationFilter.new :method_name => 'asd', :method_owner => InstrumentationFilterTest
    assert filter.applies_to?(self, :asd)
    assert_false filter.applies_to?(self, :kme)
  end

end
