require 'adsl/ds/fol_translation/state/state'

module ADSL
  module DS
    module FOLTranslation
      module State
        module StateManager

          attr_accessor :state
          attr_reader :non_state, :initial_state, :final_state
    
          def initialize_state_manager
            @non_state = ADSL::DS::FOLTranslation::State::NonState.new
            @initial_state = create_state :init_state
          end
    
          def create_state name
            state = ADSL::DS::FOLTranslation::State::State.new self, name, current_loop_context.sort_array
            state
          end
        end
      end
    end
  end
end

