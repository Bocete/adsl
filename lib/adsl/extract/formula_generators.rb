require 'adsl/lang/ast_nodes'
require 'adsl/util/general'
require 'adsl/extract/utils'
require 'adsl/extract/extraction_error'
require 'adsl/extract/rails/basic_type_extensions'

module ADSL
  module Extract

    # forward declaration
    class FormulaBuilder; end

    module FormulaGenerators
      include Utils
      include ADSL::Lang

      def in_formula_builder
        formula_builder = nil
        if self.is_a? ::ADSL::Extract::FormulaBuilder
          formula_builder = self
        else
          formula_builder = ::ADSL::Extract::FormulaBuilder.new
          formula_builder.adsl_stack << self.adsl_ast if self.respond_to? :adsl_ast
        end
        yield formula_builder
        formula_builder
      end

      def handle_quantifier(quantifier, adsl_ast_node_klass, arg_types, block)
        raise ExtractionError, "A block needs to be passed to quantifiers" if block.nil?
        raise ExtractionError, "At least some variables need to be given to the block" if block.parameters.empty?
        in_formula_builder do |fb|
          param_types = {}
          block.parameters.each do |param|
            classname = infer_classname_from_varname param[1]
            klass = Object.lookup_const classname
            param_types[param[1].to_sym] = klass
          end
          arg_types.each do |explicit_name, explicit_type|
            classname = classname_for_classname explicit_type
            klass = Object.lookup_const classname
            raise ExtractionError, "Unknown class #{explicit_type} for parameter #{explicit_name}" if klass.nil?
            param_types[explicit_name.to_sym] = klass
          end

          param_types.each do |name, klass|
            raise ExtractionError, "Unknown klass for variable `#{name}' in #{quantifier} quantifier" if klass.nil?
            raise ExtractionError, "Class #{klass.name} is not instrumented" unless klass.respond_to? :adsl_ast
          end

          vars_and_objsets = block.parameters.map{ |param|
            [
              ASTIdent[param[1].to_s],
              param_types[param[1].to_sym].all.adsl_ast
            ]
          }
          block_params = block.parameters.map do |param|
            param_types[param[1].to_sym].new :adsl_ast => ASTVariableRead.new(:var_name => ASTIdent[param[1]])
          end
          subformula = block.(*block_params)
          subformula = subformula.adsl_ast if !subformula.nil? and subformula.respond_to? :adsl_ast
          subformula = ASTBoolean.new(:bool_value => true) if subformula.nil?
          unless subformula.is_a?(ASTNode)
            raise ExtractionError, "Invalid formula #{subformula} returned by block in `#{quantifier}'"
          end
          fb.adsl_stack << adsl_ast_node_klass.new(:vars => vars_and_objsets, :subformula => subformula)
        end
      end

      def forall(arg_types = {}, &block)
        handle_quantifier :forall, ASTForAll, arg_types, block
      end

      def exists(arg_types = {}, &block)
        handle_quantifier :exists, ASTExists, arg_types, block
      end

      def not(param = nil)
        in_formula_builder do |fb|
          if param.nil?
            fb.adsl_stack << :not
          else
            subtree = param.respond_to?(:adsl_ast) ? param.adsl_ast : param
            fb.adsl_stack << ASTNot.new(:subformula => subtree)
          end
        end
      end
      alias_method :neg, :not

      def true
        in_formula_builder do |fb|
          fb.adsl_stack << true.adsl_ast
        end
      end

      def false
        in_formula_builder do |fb|
          fb.adsl_stack << false.adsl_ast
        end
      end

      def [](formula)
        in_formula_builder do |fb|
          formula = formula.adsl_ast if formula.respond_to? :adsl_ast
          fb.adsl_stack << formula
        end
      end

      def binary_op_with_any_number_of_params(op, children_key, klass, params)
        in_formula_builder do |fb|
          if params.empty?
            fb.adsl_stack << op
          else
            params.each do |param|
              raise ExtractionError, "Invalid formula `#{param}' in `#{op}' parameter list" unless param.respond_to? :adsl_ast
            end
            fb.adsl_stack << klass.new(children_key => params.map(&:adsl_ast))
          end
        end
      end

      def binary_op(op, klass, params)
        raise ExtractionError, "`#{op}' takes two parameters or none at all" unless params.empty? or params.length == 2
        in_formula_builder do |fb|
          if params.empty?
            fb.adsl_stack << op
          else
            params.each do |param|
              raise ExtractionError, "Invalid formula `#{param}' in `#{op}' parameter list" unless param.respond_to? :adsl_ast
            end
            fb.adsl_stack << klass.new(:subformula1 => params.first.adsl_ast, :subformula2 => params.last.adsl_ast)
          end
        end
      end

      def and(*params)
        binary_op_with_any_number_of_params :and, :subformulae, ASTAnd, params
      end
      
      def or(*params)
        binary_op_with_any_number_of_params :or, :subformulae, ASTOr, params
      end

      def equal(*params)
        binary_op_with_any_number_of_params :equal, :exprs, ASTEqual, params
      end
      
      def implies(*params)
        binary_op :implies, ASTImplies, params
      end
    end
    
    class FormulaBuilder
      include FormulaGenerators

      attr_reader :adsl_stack
      
      def initialize(component = nil)
        @adsl_stack = []
        @adsl_stack << component unless component.nil?
      end

      def handle_unary_operator(elements, operator)
        until (index = elements.find_index(operator)).nil?
          raise ExtractionError, "Unary operator `#{operator}' not prefix-called" if index == elements.length-1
          arg = elements[index+1]
          raise ExtractionError, "`#{arg}', used by operator `#{operator}', is not a formula" unless arg.is_a? ASTNode
          result = yield arg
          elements.delete_at index
          elements[index] = result
        end
      end
      
      def handle_binary_operator(elements, operator)
        until (index = elements.find_index(operator)).nil?
          raise ExtractionError, "Binary operator `#{operator}' not infix-called" if index == 0 or index == elements.length-1
          args = [elements[index-1], elements[index+1]]
          args.each do |arg|
            raise ExtractionError, "`#{arg}', used by operator `#{operator}', is not a formula" unless arg.is_a? ASTNode
          end
          result = yield *args
          elements.delete_at index - 1
          elements.delete_at index - 1
          elements[index - 1] = result
        end
      end

      def gather_adsl_asts
        elements = @adsl_stack.clone
        handle_unary_operator elements, :not do |formula|
          ASTNot.new(:subformula => formula)
        end
        handle_binary_operator elements, :and do |formula1, formula2|
          ASTAnd.new(:subformulae => [formula1, formula2])
        end
        handle_binary_operator elements, :or do |formula1, formula2|
          ASTOr.new(:subformulae => [formula1, formula2])
        end
        handle_binary_operator elements, :implies do |formula1, formula2|
          ASTImplies.new(:subformula1 => formula1, :subformula2 => formula2)
        end
        handle_binary_operator elements, :equal do |formula1, formula2|
          ASTEqual.new(:exprs => [formula1, formula2])
        end
        elements 
      end

      def adsl_ast
        elements = gather_adsl_asts
        if elements.length != 1
          raise ExtractionError, "Invalid formula/operator stack state [#{ elements.map{ |e| e.respond_to?(:to_adsl) ? e.to_adsl : e }.join(', ') }]"
        end
        elements.first
      end
    end
  end
end

class ADSL::Lang::ASTNode
  include ADSL::Extract::FormulaGenerators
end

class TrueClass
  include ADSL::Extract::FormulaGenerators
end

class FalseClass
  include ADSL::Extract::FormulaGenerators
end
