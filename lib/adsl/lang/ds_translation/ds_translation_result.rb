require 'adsl/ds/data_store_spec'

module ADSL
  module Lang
    module DSTranslation
      class DSTranslationResult
        container_for :state_transitions, :expr

        def type_sig
          @expr.type_sig
        end

        def noop?
          !has_side_effects? and @expr.type_sig.is_objset_type? and @expr.type_sig.cardinality.empty?
        end

        def has_side_effects?
          @state_transitions.any?
        end

        def with_expr(expr)
          DSTranslationResult.new :state_transitions => @state_transitions.dup, :expr => expr
        end
      end
    end
  end
end
