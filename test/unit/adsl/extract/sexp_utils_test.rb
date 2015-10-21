require 'adsl/util/test_helper'
require 'adsl/extract/sexp_utils'

class ADSL::Extract::SexpUtilsTest < ActiveSupport::TestCase
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

  def test_block_replace__unless_in
    sexp = s(:blah, s(:array, s(:lit, 1), s(:blah, s(:lit, 1))), s(:lit, 1))
    
    replacement = sexp.block_replace(:lit, :unless_in => :array) do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal s(:blah, s(:array, s(:lit, 1), s(:blah, s(:lit, 1))), s(:lit, 2)), replacement
    
    
    sexp = s(:blah, s(:array, s(:lit, 1), s(:blah, s(:lit, 1))), s(:lit, 1))
    
    replacement = sexp.block_replace(:lit, :unless_in => [:array]) do |sexp|
      s(:lit, sexp[1]*2)
    end

    assert_equal s(:blah, s(:array, s(:lit, 1), s(:blah, s(:lit, 1))), s(:lit, 2)), replacement
  end

  def test_find_shallowest__plain
    assert_equal [], s(s(:self)).find_shallowest(:lit)
    assert_equal [s(:lit, 1), s(:lit, 2)], s(s(:lit, 1), s(:self), s(:lit, 2), s(:self)).find_shallowest(:lit)
  end

  def test_find_shallowest__goes_through_depth
    assert_equal [s(:lit, 1), s(:lit, 2)], s(s(s(:lit, 1), s(:self), s(:lit, 2), s(:self))).find_shallowest(:lit)
    assert_equal [s(:lit, 1), s(:lit, 2)], s(s(:lit, 1), s(s(:self), s(:lit, 2), s(:self))).find_shallowest(:lit)
  end
  
  def test_find_shallowest__only_the_shallowest
    assert_equal [s(:lit, s(:lit, 2))], s(s(:lit, s(:lit, 2)), s(:self)).find_shallowest(:lit)
  end

  def test_may_return_or_raise__simple
    assert_false s(:block, s(:if, s(:true), s(:block), s(:block))).may_return_or_raise?
    assert s(:block, s(:if, s(:true), s(:block), s(:block, s(:return, s(:nil))))).may_return_or_raise?
    
    assert_false s(:block, s(:if, s(:true), s(:block), s(:block))).may_return_or_raise?
    assert s(:block, s(:if, s(:true), s(:block), s(:block, s(:call, nil, :raise)))).may_return_or_raise?
  end

  def test_may_return_or_raise__deep
    sexp = s(:if,
      s(:lasgn, :user, s(:call, s(:const, :User), :authenticate, s(:call, nil, :http_user), s(:call, nil, :http_pass))),
      s(:block,
        s(:attrasgn, s(:call, nil, :session), :[]=, s(:str, "user_id"), s(:call, s(:lvar, :user), :id)),
        s(:call, nil, :set_current_user, s(:lvar, :user)),
        s(:return, s(:true))
      ),
      nil
    )
    assert sexp.may_return_or_raise?
  end

end
