require 'test/unit'
require 'extract/sexp_utils'
require 'pp'
require 'util/test_helper'

class SexpUtilsTest < Test::Unit::TestCase
  def test_block_replace__no_match
    sexp = s(:array, s(:lit, 1), s(:lit, 2))
    
    replacement = sexp.block_replace(:call) do |a|
      "#{a}2".to_sym
    end
    assert_equal s(:array, s(:lit, 1), s(:lit, 2)), replacement
  end

  def test_block_replace__plain
    sexp = s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 0))
    
    replacement = sexp.block_replace(:array) do |a|
      Sexp.from_array [:array] + a.sexp_body.map{ |e| [:lit, e[1] * 2] }
    end

    assert_equal s(:array, s(:lit, 2), s(:lit, 4), s(:lit, 0)), replacement
  end
  
  def test_block_replace__nested
    sexp = s(:array, s(:lit, 1), s(:lit, 2), s(:array, s(:lit, 3)))
    
    replacement = sexp.block_replace(:array) do |a|
      Sexp.from_array [:array] + a.sexp_body.map{ |e| e.sexp_type == :lit ? [:lit, e[1] * 2] : e }
    end

    assert_equal s(:array, s(:lit, 2), s(:lit, 4), s(:array, s(:lit, 6))), replacement
  end
  
  def test_block_replace__deep
    sexp = s(:blah, s(:array, s(:lit, 1), s(:lit, 2)))
    
    replacement = sexp.block_replace(:lit) do |a|
      s(:lit, a[1]*2)
    end

    assert_equal s(:blah, s(:array, s(:lit, 2), s(:lit, 4))), replacement
  end
end
