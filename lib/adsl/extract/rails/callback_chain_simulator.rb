require 'adsl/parser/ast_nodes'

module ADSL
  module Extract
    module Rails
      module CallbackChainSimulator

        include ADSL::Parser
       
        # returns true or false if the node will render or raise, or will not render or raise
        # returns nil if the node may or may not render or raise
        def halting_status_of(ast_node, is_action_body = false)
          if ast_node.is_a?(ASTBlock)
            sub_statuses = ast_node.statements.map do |stmt|
              sub_rs = halting_status_of stmt, is_action_body
              return true if sub_rs
              sub_rs
            end
            return nil if sub_statuses.include? nil
            return false
          elsif ast_node.is_a?(ASTEither)
            sub_statuses = ast_node.blocks.map{ |block| halting_status_of block, is_action_body }
            return false if sub_statuses.uniq == [false]
            return true if sub_statuses.uniq == [true]
            return nil
          elsif ast_node.is_a?(ASTDummyStmt) and [:render, :raise].include?(ast_node.label)
            return false if ast_node.label == :render and is_action_body
            return true
          else
            return false
          end
        end

        # returns a hash of {:will_halt => block, :will_not_halt => block}
        def split_into_paths_that_will_or_will_not_halt(block, is_action_body = false)
          case halting_status_of block, is_action_body
          when true;  return { :will_halt => block, :will_not_halt => nil }
          when false; return { :will_halt => nil,   :will_not_halt => block }
          end
         
          paths = { :will_halt => [], :will_not_halt => [] }
          block.statements.each do |stmt|
            if stmt.is_a?(ASTBlock) && halting_status_of(stmt, is_action_body).nil?
              possibilities = split_into_paths_that_will_or_will_not_halt stmt, is_action_body

              paths[:will_halt]     << possibilities[:will_halt]
              paths[:will_not_halt] << possibilities[:will_not_halt]
            elsif stmt.is_a?(ASTEither) && halting_status_of(stmt, is_action_body).nil?
              rendering_paths     = []
              not_rendering_paths = []
              
              stmt.blocks.each do |subblock|
                possibilities = split_into_paths_that_will_or_will_not_halt subblock, is_action_body
                rendering_paths     << possibilities[:will_halt]     unless possibilities[:will_halt].nil?
                not_rendering_paths << possibilities[:will_not_halt] unless possibilities[:will_not_halt].nil?
              end

              if rendering_paths.length == 1
                paths[:will_halt] << rendering_paths.first
              else
                paths[:will_halt] << ASTEither.new(:blocks => rendering_paths)
              end

              if not_rendering_paths.length == 1
                paths[:will_not_halt] << not_rendering_paths.first
              else
                paths[:will_not_halt] << ASTEither.new(:blocks => not_rendering_paths)
              end
            else
              paths[:will_halt]     << stmt
              paths[:will_not_halt] << stmt
            end
          end

          paths[:will_halt]     = ASTBlock.new(:statements => paths[:will_halt])
          paths[:will_not_halt] = ASTBlock.new(:statements => paths[:will_not_halt])

          paths
        end

        def split_into_callbacks(root_block)
          pairs = []
          root_block.statements.reverse_each do |stmt|
            if stmt.is_a? ADSL::Parser::ASTDummyStmt
              pairs << [stmt.label, []]
            else
              pairs.last[1] << stmt
            end
          end
          pairs.reverse!
          pairs.length.times do |index|
            stmts = pairs[index][1]
            pairs[index][1] = (stmts.length == 1 ? stmts.first : ASTBlock.new(:statements => stmts.reverse))
          end

          pairs
        end

        def interrupt_callback_chain_on_render(root_block, action_name)
          callbacks = split_into_callbacks root_block

          index = action_index = callbacks.index{ |callback_name, block| callback_name == action_name } 
          return if index.nil?
           
          # skip the action and proceed to the most prior before block
          until index < 0
            block = callbacks[index][1]
            render_halts = index != action_index

            case halting_status_of block, !render_halts
            when true
              # will halt execution after this callback is done
              callbacks = callbacks.first(index + 1)
            when nil
              # may render
              paths = split_into_paths_that_will_or_will_not_halt block, !render_halts
              what_happens_unless_renders = ASTBlock.new(:statements => callbacks[index+1..-1].map{ |c| c[1] })
              callbacks = callbacks.first(index + 1)
              callbacks.last[1] = ASTEither.new(:blocks => [
                paths[:will_halt],
                ASTBlock.new(:statements => [paths[:will_not_halt], *what_happens_unless_renders])
              ])
            else
              # doesn't render, all good!
            end
            index -= 1
          end

          root_block.statements = callbacks.map{ |name, block| block }
        end
        
      end
    end
  end
end
