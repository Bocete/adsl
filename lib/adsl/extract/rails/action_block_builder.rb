require 'adsl/extract/rails/other_meta'
require 'adsl/parser/ast_nodes'

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
          @has_returned_or_raised = false
        end

        def push_frame; @stmt_frames << []; end
        def pop_frame;  @stmt_frames.pop; end

        def in_stmt_frame(*args)
          push_frame
          yield *args
        ensure
          return pop_frame
        end

        def included_already?(where, what)
          return where.map{ |e| e.equal? what }.include?(true) ||
            (
              where.last.is_a?(ADSL::Parser::ASTObjsetStmt) &&
              what.is_a?(ADSL::Parser::ASTObjsetStmt) &&
              where.last.objset == what.objset
            )
        end

        def append_stmt(stmt, options = {})
          return stmt if @has_returned_or_raised && !options[:ignore_has_returned]
          return stmt if included_already? @stmt_frames.last, stmt
          @stmt_frames.last << stmt
          stmt
        end
        alias_method :<<, :append_stmt

        def branch_choice(if_id)
          @branch_choices.each do |iter_if_id, choice|
            return choice if iter_if_id == if_id
          end
          @branch_choices << [if_id, true]
          true
        end

        def has_more_executions?
          @branch_choices.each do |if_id, choice|
            return true if choice == true
          end
          false
        end

        def increment_branch_choice
          @branch_choices.pop while !@branch_choices.empty? && @branch_choices.last[1] == false
          @branch_choices.last[1] = false unless @branch_choices.empty?
        end

        def reset
          unless has_more_executions?
            @root_paths = []
            @branch_choices = []
            @return_values = []
          end
          @has_returned_or_raised = false
          @stmt_frames = [[]]
        end

        def explore_all_choices
          while true
            begin
              reset
              increment_branch_choice

              return_value = yield
           
              do_return return_value unless @has_returned_or_raised
            rescue Exception
              do_raise unless @has_returned_or_raised
            ensure
              return common_return_value unless has_more_executions?
            end
          end
        end

        def common_supertype_of_objsets(values)
          return false if values.empty?
          values.each do |value|
            return false unless !value.is_a?(MetaUnknown) && value.respond_to?(:adsl_ast)
          end
          adsl_asts = values.reject{ |v| v.nil? }.map(&:adsl_ast)
          adsl_asts = adsl_asts.map{ |v| v.is_a?(ADSL::Parser::ASTObjsetStmt) ? v.objset : v }
          adsl_asts.each do |adsl_ast|
            return false unless adsl_ast.class.is_objset?
            # side effects should trigger only if the selection is chosen;
            # but the translation does not do this
            return false if adsl_ast.objset_has_side_effects?
          end

          common_supertype = nil
          values.each do |value|
            next if value.nil?
            if common_supertype.nil?
              common_supertype = value.class
            elsif value.class <= common_supertype
              # all is fine
            elsif common_supertype <= value.class
              common_supertype = value.class
            else
              return false
            end
          end

          common_supertype
        end

        def common_supertype_of_objset_arrays(values)
          return false if values.empty?

          values.each do |value|
            return false unless value.is_a? Array
          end
          
          return_value = []
          highest_length = values.map(&:length).max
          highest_length.times do |index|
            ct = compatible_types(values.map{ |v| v[index] })
            return false unless ct
            return_value << ct
          end
          return_value
        end

        def common_return_value
          uniq = @return_values.dup
          # avoid include? because it uses :== and metaobjects override the == operator
          if uniq.map(&:nil?).include? true
            uniq.delete_if{ |e| e.nil? }
            uniq << nil
          end

          if uniq.length == 1
            uniq.first
          elsif ct = common_supertype_of_objsets(uniq)
            objsets = uniq.map(&:adsl_ast).map{ |r| r.is_a?(ADSL::Parser::ASTObjsetStmt) ? r.objset : r }
            ct.new(:adsl_ast => ADSL::Parser::ASTOneOfObjset.new(:objsets => objsets))
          elsif ct = common_supertype_of_objset_arrays(uniq)
            highest_length = uniq.map(&:length).max
            combined_objsets = []
            highest_length.times do |index|
              objsets = uniq.map{|u| u[index]}.map(&:adsl_ast).map{ |r| r.is_a?(ADSL::Parser::ASTObjsetStmt) ? r.objset : r }
              combined_objsets << ct[index].new(:objset => ADSL::Parser::ASTOneOfObjset.new(:objsets => objsets))
            end
            combined_objsets
          else
            # append all return values to root paths
            # cause they won't be returned and handled by the caller
            # if an array is returned, assume the 'return 1, 2, 3' syntax

            @return_values.length.times do |index|
              Array.wrap(@return_values[index]).flatten.each do |ret_value|
                stmt = ADSL::Extract::Rails::ActionInstrumenter.extract_stmt_from_expr ret_value
                @root_paths[index] << stmt unless (
                  stmt.nil? ||
                  !stmt.class.is_statement? ||
                  included_already?(@root_paths[index], stmt)
                )
              end
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
          unless @has_returned_or_raised
            @root_paths << all_stmts_so_far
            @return_values << return_value
            @has_returned_or_raised = true
          end
          return_value
        end

        def do_raise(*args)
          unless @has_returned_or_raised
            # appending nothing to root paths
            @root_paths << [::ADSL::Parser::ASTDummyStmt.new(:type => :raise)]
            @return_values << nil
            @has_returned_or_raised = true
          end
          return *args
        end

        def adsl_ast
          blocks = @root_paths.map do |root_path|
            ::ADSL::Parser::ASTBlock.new :statements => root_path
          end

          if blocks.empty?
            ::ADSL::Parser::ASTBlock.new :statements => []
          elsif blocks.length == 1
            blocks.first
          else
            ::ADSL::Parser::ASTBlock.new :statements => [::ADSL::Parser::ASTEither.new(:blocks => blocks)]
          end
        end

        def root_lvl_adsl_ast
          ::ADSL::Parser::ASTBlock.new :statements => @stmt_frames.first
        end
      end

    end
  end
end
