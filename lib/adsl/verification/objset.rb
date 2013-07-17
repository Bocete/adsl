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
        Objset.new :adsl_ast => ASTSubset.new(:objset => self), :objset_type => @objset_type
      end

      def forall(&block)
        iters = block.parameters.map{ |a| [t(a[1]), Objset.allof(a[1])] }
        params_for_block = block.parameters.map{ |a| ASTVariable.new :var_name => t(a[1]) }
        Objset.new :adsl_ast => ASTForall.new(:vars => iters, :formula => block.(params_for_block))
      end

      def exists(&block)
        iters = block.parameters.map{ |a| [t(a[1]), Objset.allof(a[1])] }
        params_for_block = block.parameters.map{ |a| ASTVariable.new :var_name => t(a[1]) }
        Objset.new :adsl_ast => ASTExists.new(:vars => iters, :formula => block.(params_for_block))
      end

      def empty?
        Objset.new :adsl_ast => ASTEmpty.new(:objset => self)
      end
    end
  end
end
