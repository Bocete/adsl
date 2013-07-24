require 'adsl/extract/rails/other_meta'

module ADSL
  module Extract
    module Rails

      class ActionBlockBuilder

        attr_accessor :root_paths, :stmt_frames, :branch_choices

        def initialize
          @root_paths = []
          @stmt_frames = [[]]
          @branch_choices = []
          @return_values = []
          @has_returned = false
        end

        def in_stmt_frame
          @stmt_frames << []
          yield
        ensure
          return @stmt_frames.pop
        end

        def append_stmt(stmt, options = {})
          return stmt if @stmt_frames.last.include? stmt
          return stmt if @has_returned && !options[:ignore_has_returned]
          @stmt_frames.last << stmt
          stmt
        end
        alias_method :<<, :append_stmt

        def branch_choice(if_id)
          @branch_choices.each do |iter_if_id, choice|
            return choice if iter_if_id == if_id
          end
          @branch_choices << [if_id, false]
          false
        end

        def has_more_executions?
          @branch_choices.each do |if_id, choice|
            return true if choice == false
          end
          false
        end

        def reset
          unless has_more_executions?
            @root_paths = []
            @branch_choices = []
            @return_values = []
          end
          @has_returned = false
          @stmt_frames = [[]]
        end

        def increment_branch_choice
          @branch_choices.pop while !@branch_choices.empty? && @branch_choices.last[1] == true
          @branch_choices.last[1] = true unless @branch_choices.empty?
        end

        def explore_all_choices
          while true
            reset
            increment_branch_choice

            return_value = yield
            do_return return_value unless @has_returned

            return common_return_value unless has_more_executions?
          end
        end

        def common_return_value
          uniq = @return_values.uniq
          if uniq.length == 1
            uniq.first
          else
            # append all return values to root paths
            # cause they won't be returned and handled by the caller
            @return_values.length.times do |index|
              stmt = ADSL::Extract::Rails::ActionInstrumenter.extract_stmt_from_expr @return_values[index]
              @root_paths[index] << stmt unless stmt.nil? or @root_paths[index].include?(stmt)
            end
            
            ADSL::Extract::Rails::MetaUnknown.new
          end
        end

        def all_stmts_so_far
          stmts = []
          @stmt_frames.each do |frame|
            stmts += frame
          end
          stmts
        end

        def do_return(return_value = nil)
          return return_value if @has_returned
          @root_paths << all_stmts_so_far
          @return_values << return_value
          @has_returned = true
          return_value
        end

        def adsl_ast
          blocks = @root_paths.map do |root_path|
            ::ADSL::Parser::ASTBlock.new :statements => root_path
          end
         
          return ::ADSL::Parser::ASTBlock.new :statements => [] if blocks.empty?
          return blocks.first if blocks.length == 1
          ::ADSL::Parser::ASTBlock.new :statements => [::ADSL::Parser::ASTEither.new(:blocks => blocks)]
        end
      end

    end
  end
end
