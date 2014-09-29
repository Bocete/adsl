require 'adsl/fol/first_order_logic'

module ADSL
  module Translation
    include ADSL::FOL
    
    class State
      attr_accessor :pred_map, :name, :context_sorts

      def initialize(translator, name, *context_sorts)
        @translator = translator
        @name = @translator.register_name name
        @context_sorts = context_sorts
        @pred_map = {}
        Hash.new do |hash, sort|
        end
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
