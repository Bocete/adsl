require 'adsl/util/test_helper'
require 'adsl/prover/engine'
require 'adsl/fol/first_order_logic'

class ADSL::Prover::EngineTest < ActiveSupport::TestCase
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
    engine = Engine.new('spass', wrap_formula(true))
    engine.prepare_prover_commands
    assert_equal :correct, engine.run[:result]

    engine = Engine.new('spass', wrap_formula(false))
    engine.prepare_prover_commands
    assert_equal :incorrect, engine.run[:result]
  end
end
