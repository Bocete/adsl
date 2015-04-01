module ADSL
  module Extract
    module Rails
      class Method
        attr_reader :return_arg_classes, :return_path_count, :name, :stmt_frames

        def initialize(options = {})
          @name = options[:name]
          @action_or_callback = options[:action_or_callback]
          @stmt_frames = []
          @cancel_return = false
          @return_path_count = 0
        end
        
        def push_frame; @stmt_frames << []; end
        def pop_frame; @stmt_frames.pop; end
        def action_or_callback?
          @action_or_callback
        end

        def extract_from(&block)
          block = ADSL::Parser::ASTBlock.new :statements => in_stmt_frame(&block)

          cancel_return_stmt if action_or_callback?

          return_exprs = if @cancel_return
            # replace all return statements with expression statements
            block.remove_statements_after_returns!
            blocks_not_including_inner_guards = block.recursively_select do |elem|
              next false if elem.is_a? ADSL::Parser::ASTReturnGuard
              next true if elem.is_a? ADSL::Parser::ASTBlock
            end
            blocks_not_including_inner_guards << block
            blocks_not_including_inner_guards.each do |block|
              first_return = block.statements.index{ |s| s.is_a? ADSL::Parser::ASTReturn }
              if first_return
                block.statements = block.statements.first(first_return + 1)
                return_stmt = block.statements.pop
                return_stmt.exprs.each do |expr|
                  block.statements << ADSL::Parser::ASTExprStmt.new(:expr => expr)
                end
              end
            end
            []
          elsif @return_arg_classes && @return_path_count == 1 && block.statements.last.is_a?(ADSL::Parser::ASTReturn)
            return_stmt = block.statements.pop
            @return_arg_classes.length.times.map do |i|
              @return_arg_classes[i].new :adsl_ast => return_stmt.exprs[i]
            end
          elsif @return_arg_classes
            block = ADSL::Parser::ASTReturnGuard.new :block => block
            @return_arg_classes.length.times.map do |i|
              @return_arg_classes[i].new :adsl_ast => ::ADSL::Parser::ASTReturned.new(:return_guard => block, :index => i)
            end
          else
            []
          end

          return_exprs = return_exprs.first if return_exprs && return_exprs.length == 1

          return block, return_exprs
        end

        def in_stmt_frame(*args)
          popped_frame = false
          push_frame
          yield *args
          popped_frame = true
          return pop_frame
        ensure
          pop_frame unless popped_frame
        end

        def included_already?(where, what)
          return where.map{ |e| e.equal? what }.include?(true) ||
            (
              where.last.is_a?(ADSL::Parser::ASTExprStmt) &&
              what.is_a?(ADSL::Parser::ASTExprStmt) &&
              where.last.expr == what.expr
            )
        end

        def append_stmt(stmt, options = {})
          @stmt_frames.last << stmt unless included_already? @stmt_frames.last, stmt
          stmt
        end
        alias_method :<<, :append_stmt

        def peek_last_expr
          stmts = @stmt_frames.last
          if !stmts.empty? && stmts.last.is_a?(ADSL::Parser::ASTExprStmt)
            return stmts.last.expr
          end
        end

        def pop_last_expr
          stmts = @stmt_frames.last
          if !stmts.empty? && stmts.last.is_a?(ADSL::Parser::ASTExprStmt)
            return stmts.pop.expr
          end
        end

        def set_return_types(classes)
          @return_path_count += 1
          classes.each do |c|
            unless c == NilClass || c < ActiveRecord::Base
              cancel_return_stmt
              return
            end
          end
          if @return_arg_classes.nil?
            @return_arg_classes = classes
          else
            raise "Invalid number of return args" if @return_arg_classes.length != classes.length
            classes.each_index do |i|
              next if classes[i] == NilClass
              if @return_arg_classes[i] > classes[i]
                @return_arg_classes[i] = classes[i]
              elsif @return_arg_classes[i] <= classes[i]
                # nothing
              else
                # incompatible return types
                cancel_return_stmt
              end
            end
          end
        end

        def cancel_return_stmt
          @cancel_return = true
        end
      end
    end
  end
end
