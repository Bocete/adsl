require 'adsl/parser/ast_nodes'

module ADSL
  module Verification
    class Objset
      include ADSL::Parser
      include ADSL::Verification::Utils
      extend ADSL::Verification::Utils

      def self.allof(klass)
        klass_name = classname_for_classname(klass)
        Objset.new :adsl_ast => ASTAllOf.new(:class_name => t(klass_name)), :objset_type => klass_name
      end

      attr_accessor :adsl_ast, :objset_type

      def initialize(options = {})
        @adsl_ast = options[:adsl_ast]
        @objset_type = options[:objset_type]
      end

      def subset
        Objset.new :adsl_ast => ASTSubset.new(:objset => self.adsl_ast), :objset_type => @objset_type
      end

      def empty?
        Objset.new :adsl_ast => ASTEmpty.new(:objset => self.adsl_ast)
      end

      def method_missing(method, *args, &block)
        Objset.new :adsl_ast => ASTDereference.new(:objset => self.adsl_ast, :rel_name => t(method))
      end

      def forall(&block)
        iters = block.parameters.map{ |a| [t(a[1]), self.adsl_ast] }
        params_for_block = block.parameters.map{ |a| ASTVariable.new :var_name => t(a[1]) }
        ASTForall.new(:vars => iters, :formula => block.(params_for_block))
      end

      def exists(&block)
        iters = block.parameters.map{ |a| [t(a[1]), self.adsl_ast] }
        params_for_block = block.parameters.map{ |a| ASTVariable.new :var_name => t(a[1]) }
        ASTExists.new(:vars => iters, :formula => block.(params_for_block))
      end
    end
  end
end
