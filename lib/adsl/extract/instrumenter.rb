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
      attr_accessor :instrumentation_filters
      
      @instance = nil

      def self.get_instance()
        @instance
      end

      def ruby_parser
        RUBY_VERSION >= '2' ? Ruby19Parser.new : RubyParser.for_current_ruby
      end

      def self.instrumented()
        # a dummy method injected into the AST
      end

      def exec_within
        Instrumenter.instance_variable_set(:@instance, self) if @stack_depth == 0
        @stack_depth += 1

        return yield(self)
      ensure
        @stack_depth -= 1
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
        return
      end

      def initialize(instrument_domain = Dir.pwd)
        @instrument_domain = instrument_domain
        @replacers = []
        @stack_depth = 0

        # mark the instrumentation
        replace :defn, :defs do |sexp|
          mark_sexp_instrumented sexp
        end

        # make sure the instrumentation propagates through calls
        replace :call do |sexp|
          # expected format: s(:call, object, method_name, *args)
          # replaced with Extract::Instrumenter.e(instrumenter_id, object, method_name, *args)
          #
          # if the last arg is a s(:block_pass), unroll it into a proper block
          original_object = sexp.sexp_body[0] || s(:self)
          original_method_name = sexp.sexp_body[1]
          original_args = sexp.sexp_body[2..-1]

          next sexp if [s(:self), nil].include? original_object and Kernel.respond_to? original_method_name

          result = s(:call, nil, :ins_call, original_object, s(:lit, original_method_name), *original_args)
          if result.sexp_body.last.sexp_type == :block_pass
            block = result.last.sexp_body[0]
            
            if block.sexp_type == :lit
              result = s(:iter, result[0..-2], s(:args, :e), s(:call, nil, :ins_call, s(:call, nil, :e), block))
            else
              raise "not supported"
            end
          end
          result
        end
      end

      def should_instrument?(object, method_name)
        return false if object.is_a?(Numeric) or object.is_a?(Symbol)
       
        method = object.singleton_class.instance_method method_name

        return false if method.source_location.nil?

        source_full_path = method.source_location.first
        unless source_full_path.start_with?("/")
          source_full_path = File.join Dir.pwd, source_full_path
        end

        return false if method.owner == Kernel
        return false if @instrument_domain && !(source_full_path =~ /^#{@instrument_domain}.*$/)

        (instrumentation_filters || []).each do |filter|
          return false unless filter.allow_instrumentation? object, method_name
        end
        
        source = method.source
        sexp = ruby_parser.process source
        !sexp_instrumented? sexp
      rescue MethodSource::SourceNotFoundError
        # sometimes this happens because the method_source gem bugs out with evals etc
        return false
      rescue NameError => e
        # ghost method with no available source
        return false
      end

      def replace(*types, &block)
        options = types.last.is_a?(Hash) ? types.pop : {}
        @replacers << [types, block, options]
      end

      def with_replace(*types, replacer)
        replace *types, replacer
        yield
      ensure
        @replacers.pop
      end

      def execute_instrumented(object, method_name, *args, &block)
        self.exec_within do
          instrument object, method_name
          object.send(method_name, *args, &block)
        end
      end

      def convert_root_defs_into_defn(sexp)
        sexp.sexp_type == :defs ? s(:defn, *sexp[2..-1]) : sexp
      end

      def instrument_string(source)
        sexp = ruby_parser.process source
        unless sexp.nil?
          instrumented_sexp = instrument_sexp sexp
          new_code = Ruby2Ruby.new.process instrumented_sexp
        else
          source
        end
      end

      def instrument(object, method_name)
        if should_instrument? object, method_name
          begin
            # this is overly complicated because I want to avoid using .method on non-class objects
            # because they might implement method themselves
            method = object.singleton_class.instance_method method_name
            
            source = method.source
            
            sexp = ruby_parser.process source

            unless sexp.nil?
              sexp = convert_root_defs_into_defn sexp

              instrumented_sexp = instrument_sexp sexp

              new_code = Ruby2Ruby.new.process instrumented_sexp

              object.replace_method method_name, new_code

              new_code
            else
              source
            end
          rescue MethodSource::SourceNotFoundError
          end
        end
      end

      def instrument_sexp(sexp)
        return nil if sexp.nil?
        @replacers.reverse_each do |types, block, options|
          sexp = sexp.block_replace *types, options, &block
        end
        sexp
      end

    end
  end
end
