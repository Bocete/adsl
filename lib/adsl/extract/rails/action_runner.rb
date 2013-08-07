require 'adsl/parser/ast_nodes'

module ADSL
  module Extract
    module Rails
      class ActionRunner
        include ::ADSL::Parser

        attr_reader :controller, :action

        def initialize(controller, action)
          @controller = controller
          @action = action
        end

        def callbacks
          @controller._process_action_callbacks
        end

        def root_paths_to_stmts(root_paths)
          return root_paths.first.statements if root_paths.length == 1
          [ASTEither.new(:blocks => root_paths)]
        end

        def run_action


          action_root_paths = action_adsl_ast.blocks.map{ |block| [block, false] }
        end

        def run_before_filter(higher_root_paths)
          filter_root_paths = 

          filter_root_paths.each do |block, chain_halted|
            block += root_paths_to_stmts(higher_root_paths) unless chain_halted
          end

          filter_root_paths
        end

        def run_after_filter(higher_root_paths)
          filter_root_paths =

          higher_root_paths.each do |block, chain_halted|
            block += root_paths_to_stmts(filter_root_paths) unless chain_halted
          end

          higher_root_paths
        end

        def run_around_filter

        end
      end
    end
  end
end
