require 'adsl/fol/first_order_logic'
require 'adsl/lang/ast_nodes'

module ADSL
  module DS
    module FOLTranslation
      module State
        include ADSL::FOL

        class NonState
          def [](*ps, o)
            raise ADSL::Lang::ADSLError, "NonState can only be used outside contexts (#{ps})" unless ps.flatten.empty?
            true
          end

          def registered_sorts
            []
          end

          def link_to_previous_state
            raise ADSL::Lang::ADSLError, "NonState cannot be linked to other states sequentially"
          end

          def sort_difference(other)
            raise ADSL::Lang::ADSLError, "NonState cannot be linked to other states sequentially"
          end
        end
        
        class State
          attr_accessor :pred_map, :name, :context_sorts

          def initialize(translator, name, *context_sorts)
            @translator = translator
            @name = @translator.register_name name
            @context_sorts = context_sorts
            @pred_map = {}
          end

          def sorted_predicate(sort, create = true)
            pred = @pred_map[sort]
            if pred.nil?
              return @previous_state.sorted_predicate sort, create if @previous_state
              return nil unless create
              pred = @translator.create_predicate "#{@name}_#{sort.name}", *@context_sorts, sort
              @pred_map[sort] = pred
            end
            pred
          end

          def [](*ps, o)
            raise "Unknown sort for `#{o}`" unless o.respond_to? :to_sort
            pred = sorted_predicate o.to_sort
            pred[ps, o]
          end

          def registered_sorts
            @pred_map.keys
          end

          def link_to_previous_state(state)
            @previous_state = state
          end

          # returns a set of sorts for which these two states have different states
          def sort_difference(other)
            potential_difference = (self.pred_map.keys + other.pred_map.keys).uniq

            potential_difference.select do |sort|
              pred1 = self.sorted_predicate sort, false
              pred2 = other.sorted_predicate sort, false
              pred1 != pred2
            end
          end
        end
      end
    end
  end
end
