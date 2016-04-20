require 'set'

module ADSL
  module Extract
    module Rails

      class Method
        attr_reader :name

        def initialize(options = {})
          @return_types = []
          @name = options[:name]
        end

        def is_root_level?
          false
        end

        def report_return_type(type)
          @return_types << type
        end

        def self.ancestors(types, index)
          Set[types.map{ |t| t.ancestors[index] }]
        end

        def return_type
          @return_types.delete NilClass
          @return_types.reject!{ |c| c <= ADSL::Lang::ASTNode }
          @return_types.uniq!
          return if @return_types.empty?
          if @return_types.all?{ |c| c < ActiveRecord::Base }
            if @return_types.length == 1
              @return_types.first
            else
              min_index = -1 * @return_types.map{ |t| t.ancestors.length }.min
             
              while Method.ancestors(@return_types, min_index).count > 1
                min_index += 1
              end
              
              sample = @return_types.first.ancestors[min_index]
              sample if sample < ActiveRecord::Base
            end
          end
        end

        def extract_from
          return_value = yield
          original_expressions = [return_value].flatten
          
          adsl_ast_exprs = original_expressions.map(&:try_adsl_ast).compact

          unless adsl_ast_exprs.all? &:noop?
            block = ADSL::Lang::ASTBlock.new :exprs => adsl_ast_exprs
            if original_expressions.last.is_a?(ActiveRecord::Base)
              original_expressions.last.class.new :adsl_ast => block
            else
              block
            end
          else
            return return_value
          end
        end
      end

      class RootMethod < Method
        attr_accessor :root_block

        def initialize
          super :name => :root
          @root_block = ADSL::Lang::ASTBlock.new :exprs => []
        end

        def is_root_level?
          true
        end
      end

    end
  end
end
