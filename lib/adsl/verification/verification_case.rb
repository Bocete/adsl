require 'test/unit'
require 'adsl/parser/ast_nodes'
require 'adsl/verification/utils'
require 'adsl/verification/formula_generators'

module ADSL
  module Verification
    class VerificationCase < Test::Unit::TestCase
      include ::ADSL::Verification::Utils
      include ::ADSL::Verification::FormulaGenerators
    end
  end
end
