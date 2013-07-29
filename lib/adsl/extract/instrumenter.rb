require 'backports'
require 'sexp_processor'
require 'ruby_parser'
require 'method_source'
require 'ruby2ruby'
require 'adsl/extract/sexp_utils'
require 'adsl/extract/meta'

module Kernel
  def ins_call(object, method_name, *args, &block)
    ::ADSL::Extract::Instrumenter.get_instance.execute_instrumented object, method_name, *args, &block
  end
end

module ADSL
  module Extract
    class Instrumenter
      
      attr_reader :stack_depth
      
      @instance = nil
      @method_locals_stack = []

      def self.get_instance()
        @instance
      end

      def ruby_parser
        RUBY_VERSION >= '2' ? Ruby19Parser.new : RubyParser.for_current_ruby
      end

      def self.instrumented()
        # a dummy method injected into the AST
      end

      def method_locals
        @method_locals_stack.last
      end

      def previous_locals
        @method_locals_stack[-2]
      end

      def root_locals
        @method_locals_stack.first
      end

      def exec_within
        Instrumenter.instance_variable_set(:@instance, self) if @stack_depth == 0
        @stack_depth += 1
        @method_locals_stack << create_locals if respond_to? :create_locals

        return yield(self)
      ensure
        @stack_depth -= 1
        @method_locals_stack.pop
        Instrumenter.instance_variable_set(:@instance, nil) if @stack_depth == 0
      end

      def mark_sexp_instrumented(sexp)
        raise 'Already instrumented' if sexp_instrumented? sexp
        
        first_stmt = sexp[3]

        if first_stmt[0] != :call or
            first_stmt[1] != Instrumenter.to_sexp or
            first_stmt[2] != :instrumented
          new_stmt = s(:call, Instrumenter.to_sexp, :instrumented)
          sexp.insert 3, new_stmt
        end
        sexp
      end

      def sexp_instrumented?(sexp)
        first_stmt = sexp[3]
        return (first_stmt[0] == :call and
            first_stmt[1] == Instrumenter.to_sexp and
            first_stmt[2] == :instrumented)
      rescue MethodSource::SourceNotFoundError
        return nil
      end

      def initialize(instrument_domain = nil)
        @instrument_domain = instrument_domain
        @replacers = []
        @stack_depth = 0
        @method_locals_stack = []

        # mark the instrumentation
        replace :defn, :defs do |sexp|
          mark_sexp_instrumented sexp
        end

        # make sure the instrumentation propagates through calls
        replace :call do |sexp|
          # expected format: s(:call, object, method_name, *args)
          # replaced with Extract::Instrumenter.e(instrumenter_id, object, method_name, *args)
          original_object = sexp.sexp_body[0] || s(:self)
          original_method_name = sexp.sexp_body[1]
          original_args = sexp.sexp_body[2..-1]

          next sexp if [s(:self), nil].include? original_object and Kernel.respond_to? original_method_name

          s(:call, nil, :ins_call, original_object, s(:lit, original_method_name), *original_args)
        end
      end

      def should_instrument?(object, method_name)
        method = object.method method_name
        return false if method.source_location.nil?
        return true if @instrument_domain.nil? || method.source_location =~ /^#{@instrument_domain}.*$/
        source = method.source
        sexp = ruby_parser.process source
        !sexp_instrumented? sexp
      rescue MethodSource::SourceNotFoundError
        # sometimes this happens because the method_source gem bugs out with evals etc
        return false
      end

      def replace(*types, &block)
        @replacers << [types, block]
      end

      def execute_instrumented(object, method_name, *args, &block)
        self.exec_within do
          instrument object, method_name
          return object.send method_name, *args, &block
        end
      end

      def convert_root_defs_into_defn(sexp)
        sexp.sexp_type == :defs ? s(:defn, *sexp[2..-1]) : sexp
      end

      def instrument(object, method_name)
        if should_instrument? object, method_name
          begin
            method = object.method method_name
            source = method.source
            
            # Ruby 2.0.0 support is in development as of writing this
            sexp = ruby_parser.process source

            sexp = convert_root_defs_into_defn sexp

            instrumented_sexp = instrument_sexp sexp
            
            new_code = Ruby2Ruby.new.process instrumented_sexp

            object.replace_method method_name, new_code

            return new_code
          rescue MethodSource::SourceNotFoundError
          end
        end
      end

      def instrument_sexp(sexp)
        @replacers.reverse_each do |types, block|
          sexp = sexp.block_replace *types, &block
        end
        sexp
      end
    end
  end
end
