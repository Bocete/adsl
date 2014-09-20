require 'adsl/prover/engine'
require 'adsl/fol/first_order_logic'
require 'adsl/util/test_helper'
require 'test/unit'

class ADSL::Prover::EngineTest < Test::Unit::TestCase
  include ADSL::FOL
  include ADSL::Prover

  def wrap_formula(formula)
    Theorem.new(:conjecture => formula)
  end

  def test__provers
    assert_set_equal ['spass', 'z3'], Engine.new(['spass', 'z3'], wrap_formula(true)).provers
    assert_set_equal ['spass'], Engine.new('spass', wrap_formula(true)).provers
    assert_set_equal ['z3'], Engine.new('z3', wrap_formula(true)).provers
  end

  def test__trivially_correct
    assert_equal :correct,   Engine.new('spass', wrap_formula(true)).run[:result]
    assert_equal :incorrect, Engine.new('spass', wrap_formula(false)).run[:result]
  end
end
