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

        def interrupt_callback_chain_on_render(root_block, action_name)
          stmts = root_block.statements
          index = stmts.index{ |stmt| stmt.is_a?(ADSL::Parser::ASTDummyStmt) && stmt.type == action_name }
          if index.nil?
            pp root_block
            raise "Action block not found in instrumented execution"
          end
          # skip the action and proceed to the most prior before block
          index -= 3
          until index < 0
            block = stmts[index]

            case render_status_of block
            when true
              # will always render
              root_block.statements = root_block.statements.first(index + 1)
            when nil
              paths = split_into_paths_that_must_or_may_not_render block
              what_happens_unless_renders = root_block.statements[index+1..-1]
              root_block.statements = root_block.statements.first(index)
              root_block.statements << ASTEither.new(:blocks => [
                paths[:render],
                ASTBlock.new(:statements => [paths[:not_render], *what_happens_unless_renders])
              ])
            else
            end

            index -= 2
          end
        end
        
      end
    end
  end
end
