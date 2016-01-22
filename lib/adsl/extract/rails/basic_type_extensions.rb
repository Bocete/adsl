require 'adsl/parser/ast_nodes'
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

class FixedNum
  def adsl_ast
    ADSL::Parser::ASTNumber.new :value => self
  end

  def self.type_example
    self.round? ? 1 : 1.5
  end

  def type_example
    self.class.type_example
  end

  def ds_type
    self.round? ? ADSL::DS::TypeSig::BasicType::INT : ADSL::DS::TypeSig::BasicType::REAL
  end
end

class String
  def adsl_ast
    ADSL::Parser::ASTString.new :value => self
  end

  def self.type_example
    'asd'
  end

  def type_example
    self.class.type_example
  end

  def ds_type
    ADSL::DS::TypeSig::BasicType::STRING
  end
end

module ADSL
  module Extract
    module Rails

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
          when BasicType::INT
            1
          when BasicType::DECIMAL, BasicType::REAL
            1.5
          when BasicType::STRING
            'asd'
          when BasicType::BOOL
            true
          else
            raise "Unknown basic type: #{@ds_type}"
          end
        end

        def adsl_ast
          case @ds_type
          when BasicType::INT, BasicType::DECIMAL, BasicType::REAL
            ADSL::Parser::ASTNumber.new :value => nil
          when BasicType::STRING
            ADSL::Parser::ASTString.new :value => nil
          when BasicType::BOOL
            ADSL::Parser::ASTBoolean.new :bool_value => nil
          else
            raise "Unknown basic type: #{@ds_type}"
          end
        end

        def method_missing(*args)
          self
        end
      end

    end
  end
end
