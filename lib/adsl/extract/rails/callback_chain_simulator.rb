require 'adsl/parser/ast_nodes'

module ADSL
  module Extract
    module Rails
      module CallbackChainSimulator

        include ADSL::Parser
       
        # returns true or false if the node will render or may not render
        # returns nil if the node may or may not render
        def render_status_of(ast_node)
          if ast_node.is_a?(ASTBlock)
            sub_statuses = ast_node.statements.map do |stmt|
              sub_rs = render_status_of stmt
              return true if sub_rs
              sub_rs
            end
            return nil if sub_statuses.include? nil
            return false
          elsif ast_node.is_a?(ASTEither)
            sub_statuses = ast_node.blocks.map{ |block| render_status_of(block) }
            return false if sub_statuses.uniq == [false]
            return true if sub_statuses.uniq == [true]
            return nil
          elsif ast_node.is_a?(ASTDummyStmt) and ast_node.type == :render
            return true
          else
            return false
          end
        end

        # returns a hash of {:render => block, :not_render => block}
        def split_into_paths_that_must_or_may_not_render(block)
          case render_status_of block
          when true;  return { :render => block, :not_render => nil }
          when false; return { :render => nil, :not_render => block }
          end
         
          paths = { :render => [], :not_render => [] }
          block.statements.each do |stmt|
            if stmt.is_a?(ASTBlock) && render_status_of(stmt).nil?
              possibilities = split_into_paths_that_must_or_may_not_render stmt

              paths[:render]     << possibilities[:render]
              paths[:not_render] << possibilities[:not_render]
            elsif stmt.is_a?(ASTEither) && render_status_of(stmt).nil?
              rendering_paths     = []
              not_rendering_paths = []
              
              stmt.blocks.each do |subblock|
                possibilities = split_into_paths_that_must_or_may_not_render subblock
                rendering_paths     << possibilities[:render]     unless possibilities[:render].nil?
                not_rendering_paths << possibilities[:not_render] unless possibilities[:not_render].nil?
              end

              if rendering_paths.length == 1
                paths[:render] << rendering_paths.first
              else
                paths[:render] << ASTEither.new(:blocks => rendering_paths)
              end

              if not_rendering_paths.length == 1
                paths[:not_render] << not_rendering_paths.first
              else
                paths[:not_render] << ASTEither.new(:blocks => not_rendering_paths)
              end
            else
              paths[:render]     << stmt
              paths[:not_render] << stmt
            end
          end

          paths[:render]     = ASTBlock.new(:statements => paths[:render])
          paths[:not_render] = ASTBlock.new(:statements => paths[:not_render])

          paths
        end

        def split_into_callbacks(root_block)
          pairs = []
          root_block.statements.reverse_each do |stmt|
            if stmt.is_a? ADSL::Parser::ASTDummyStmt
              pairs << [stmt.type, []]
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

          index = callbacks.index{ |callback_name, block| callback_name == action_name } 
          if index.nil?
            pp callbacks
            raise "Action `#{action_name}' block not found in instrumented execution"
          end

          # skip the action and proceed to the most prior before block
          until index < 0
            block = callbacks[index][1]

            case render_status_of block
            when true
              # will always render
              callbacks = callbacks.first(index + 1)
            when nil
              # may render
              paths = split_into_paths_that_must_or_may_not_render block
              what_happens_unless_renders = ASTBlock.new(:statements => callbacks[index+1..-1].map{ |c| c[1] })
              callbacks = callbacks.first(index + 1)
              callbacks.last[1] = ASTEither.new(:blocks => [
                paths[:render],
                ASTBlock.new(:statements => [paths[:not_render], *what_happens_unless_renders])
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
