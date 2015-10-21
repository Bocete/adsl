require 'adsl/util/test_helper'
require 'adsl/util/partial_ordered'

module ADSL::Util
  class ComparableObject
    attr_accessor :num

    def intialize(num)
      @num = num
    end

    include ADSL::Util::PartialOrdered

    def compare(other)
      return nil if @num.nil? or other.num.nil?
      return -1 if @num < other.num
      return 0 if @num == other.num
      return 1 if @num > other.num
      return nil
    end
  end

  class PartialOrderedTest < ActiveSupport::TestCase
    def partial_order__loaded
      a = ComparableObject.new
      [:<, :<=, :>, :>=].each do |sym|
        a.responds_to? sym
      end
    end

    def partial_order__exists
      zero = ComparableObject.new 0
      one  = ComparableObject.new 1
      two  = ComparableObject.new 2
      assert       zero < one
      assert       zero < two
      assert       zero <= two
      assert       zero <= zero
      assert       one > zero
      assert       one >= one
      assert_false one > one
      assert_false one > two
    end

    def partial_order__undefined
      zero = ComparableObject.new 0
      nope = ComparableObject.new nil
      assert_false zero <  nope
      assert_false zero >  nope
      assert_false zero <= nope
      assert_false zero >= nope
    end
  end
end
