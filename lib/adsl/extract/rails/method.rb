module ADSL
  module Extract
    module Rails

      class Method
        attr_reader :name

        def initialize(options = {})
          @name = options[:name]
        end

        def is_root_level?
          false
        end

        def extract_from
          original_expressions = [yield].flatten
          
          block = ADSL::Lang::ASTBlock.new :exprs => original_expressions.map(&:try_adsl_ast).compact

          if original_expressions.last.is_a?(ActiveRecord::Base)
            original_expressions.last.class.new :adsl_ast => block
          else
            block
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
