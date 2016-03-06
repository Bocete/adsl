require 'adsl/ds/fol_translation/loop_context/loop_context'

module ADSL
  module DS
    module FOLTranslation
      module LoopContext
        module LoopContextManager
          attr_accessor :current_loop_context

          def initialize_loop_context_manager
            @loop_contexts = []
            @root_loop_context = create_loop_context 'root_context', true, nil, nil
            @current_loop_context = root_loop_context
          end

          def root_loop_context
            @root_loop_context
          end

          def all_loop_contexts
            @loop_contexts
          end

          def create_loop_context(name, flat, sort, parent)
            if flat
              context = FlatLoopContext.new self, name, sort, parent
            else
              context = ChainedLoopContext.new self, name, sort, parent
            end
            @loop_contexts << context
            context
          end
        end
      end
    end
  end
end
