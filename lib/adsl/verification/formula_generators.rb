require 'adsl/verification/utils'
require 'adsl/parser/ast_nodes'
require 'adsl/util/general'
require 'adsl/verification/objset'

module ADSL
  module Verification

    # forward declaration
    class FormulaBuilder; end

    module FormulaGenerators
      include Utils
      include ADSL::Parser

      def in_formula_builder
        formula_builder = nil
        if self.is_a?(FormulaBuilder)
          formula_builder = self
        else
          formula_builder = FormulaBuilder.new
          formula_builder.adsl_stack << self.adsl_ast if self.respond_to? :adsl_ast
        end
        yield formula_builder
        formula_builder
      end

      def handle_quantifier(quantifier, klass, arg_types, block)
        raise "A block needs to be passed to quantifiers" if block.nil?
        raise "At least some variables need to be given to the block" if block.parameters.empty?
        in_formula_builder do |fb|
          
          param_types = {}
          block.parameters.each do |param|
            param_types[param[1]] = infer_classname_from_varname param[1]
          end
          arg_types.each do |explicit_name, explicit_type|
            param_types[explicit_name.to_sym] = classname_for_classname explicit_type
          end

          param_types.each do |param_name, param_type|
            raise "Unknown type #{param_type} for parameter #{param_name}" if Object.lookup_const(param_type).nil?
          end

          vars_and_objsets = block.parameters.map{ |param|
            [
              t(param[1]),
              Objset.allof(param_types[param[1]]).adsl_ast
            ]
          }
          subformula = block.(*block.parameters.map{ |param| Objset.new :adsl_ast => ASTVariable.new(:var_name => t(param[1])) })
          subformula = true if subformula.nil?
          raise "Invalid formula returned by block in `#{quantifier}'" unless subformula.respond_to? :adsl_ast 
          fb.adsl_stack << klass.new(:vars => vars_and_objsets, :subformula => subformula.adsl_ast)
        end
      end

      def allof(klass)
        Objset.allof klass
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
            fb.adsl_stack << ASTNot.new(:subformula => param.adsl_ast)
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

      def binary_op_with_any_number_of_params(op, klass, params)
        in_formula_builder do |fb|
          if params.empty?
            fb.adsl_stack << op
          else
            params.each do |param|
              raise "Invalid formula in `#{op}' parameter list" unless param.respond_to? :adsl_ast
            end
            fb.adsl_stack << klass.new(:subformulae => params.map(&:adsl_ast))
          end
        end
      end

      def binary_op(op, klass, params)
        raise "`#{op}' takes two parameters or none at all" unless params.empty? or params.length == 2
        in_formula_builder do |fb|
          if params.empty?
            fb.adsl_stack << op
          else
            params.each do |param|
              raise "Invalid formula in `#{op}' parameter list" unless param.respond_to? :adsl_ast
            end
            fb.adsl_stack << klass.new(:subformula1 => params.first.adsl_ast, :subformula2 => params.last.adsl_ast)
          end
        end
      end

      def and(*params)
        binary_op_with_any_number_of_params :and, ASTAnd, params
      end
      
      def or(*params)
        binary_op_with_any_number_of_params :or, ASTOr, params
      end

      def equiv(*params)
        binary_op_with_any_number_of_params :equiv, ASTEquiv, params
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
          raise "Unary operator `#{operator}' not prefix-called" if index == elements.length-1
          arg = elements[index+1]
          raise "`#{arg}', used by operator `#{operator}', is not a formula" unless arg.is_a? ASTNode
          result = yield arg
          elements.delete_at index
          elements[index] = result
        end
      end
      
      def handle_binary_operator(elements, operator)
        until (index = elements.find_index(operator)).nil?
          raise "Binary operator `#{operator}' not infix-called" if index == 0 or index == elements.length-1
          args = [elements[index-1], elements[index+1]]
          args.each do |arg|
            raise "`#{arg}', used by operator `#{operator}', is not a formula" unless arg.is_a? ASTNode
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
        handle_binary_operator elements, :equiv do |formula1, formula2|
          ASTEquiv.new(:subformula1 => formula1, :subformula2 => formula2)
        end
        elements 
      end

      def adsl_ast
        elements = gather_adsl_asts
        raise "Unknown operators #{elements.select{ |a| a.is_a? Symbol}.map(&:to_s).join(", ")}" if elements.length > 1
        elements.first
      end
    end
  end
end

class TrueClass
  include ADSL::Verification::FormulaGenerators

  def adsl_ast
    ASTBoolean.new(:bool_value => self)
  end
end

class FalseClass
  include ADSL::Verification::FormulaGenerators
  
  def adsl_ast
    ASTBoolean.new(:bool_value => self)
  end
end
