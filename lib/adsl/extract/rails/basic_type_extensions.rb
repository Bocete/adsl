require 'adsl/lang/ast_nodes'
require 'adsl/ds/type_sig'

class TrueClass
  def adsl_ast
    ASTBoolean.new(:bool_value => self)
  end

  def self.type_example
    true
  end

  def type_example
    self.class.type_example
  end

  def ds_type
    ADSL::DS::TypeSig::BasicType::BOOL
  end
end

class FalseClass
  def adsl_ast
    ASTBoolean.new(:bool_value => self)
  end

  def self.type_example
    false
  end

  def type_example
    self.class.type_example
  end

  def ds_type
    ADSL::DS::TypeSig::BasicType::BOOL
  end
end

class Object
  def try_adsl_ast(opt_if_failed = ::ADSL::Lang::ASTEmptyObjset.new)
    ast = respond_to?(:adsl_ast) ? adsl_ast : self
    ast.is_a?(ADSL::Lang::ASTNode) ? ast : opt_if_failed
  end
end

module ADSL
  module Extract
    module Rails

      class ArrayOfBasicType < Array
        include ADSL::DS::TypeSig

        attr_reader :ds_type

        def initialize(ds_type)
          @ds_type = ds_type
        end

        def type_example
          [self[0]]
        end

        def [](*args)
          UnknownOfBasicType.new @ds_type
        end

        def []=(index, arg)
          arg
        end

        def method_missing(*args)
          self
        end
      end

      # this represents an unknown value
      # of a known basic type
      class UnknownOfBasicType
        include ADSL::DS::TypeSig

        attr_reader :ds_type

        def initialize(ds_type)
          @ds_type = ds_type
        end

        def type_example
          case @ds_type
          # when BasicType::INT
          #   1
          # when BasicType::DECIMAL, BasicType::REAL
          #   1.5
          #when BasicType::STRING
          #  'string'
          when BasicType::BOOL
            true
          else
            raise "Unknown basic type: #{@ds_type}"
          end
        end

        def adsl_ast
          case @ds_type
          # when BasicType::INT, BasicType::DECIMAL, BasicType::REAL
          #   ADSL::Lang::ASTNumber.new :value => nil
          # when BasicType::STRING
          #   ADSL::Lang::ASTString.new :value => nil
          when BasicType::BOOL
            ADSL::Lang::ASTBoolean.new :bool_value => nil
          else
            raise "Unknown basic type: #{@ds_type}"
          end
        end

        def to_ary
          ArrayOfBasicType.new @ds_type
        end

        def method_missing(*args)
          self
        end
      end

    end
  end
end
