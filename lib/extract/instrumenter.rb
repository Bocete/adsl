require 'backports'
require 'sexp_processor'
require 'extract/sexp_utils'
require 'extract/meta'
require 'ruby_parser'
require 'method_source'
require 'ruby2ruby'

module Extract
  class Instrumenter
    @instance = nil

    def self.get_instance()
      @instance
    end

    def self.sexp_class_rep
      s(:colon2, s(:colon3, :Extract), :Instrumenter)
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

      return yield
    ensure
      @stack_depth -= 1
      Instrumenter.instance_variable_set(:@instance, nil) if @stack_depth == 0
    end

    def mark_sexp_instrumented(sexp)
      raise 'Already instrumented' if sexp_instrumented? sexp
      
      first_stmt = sexp[3]

      if first_stmt[0] != :call or
          first_stmt[1] != Instrumenter.sexp_class_rep or
          first_stmt[2] != :instrumented
        new_stmt = s(:call, Instrumenter.sexp_class_rep, :instrumented)
        sexp.insert 3, new_stmt
      end
      sexp
    end

    def sexp_instrumented?(sexp)
      first_stmt = sexp[3]
      return (first_stmt[0] == :call and
          first_stmt[1] == Instrumenter.sexp_class_rep and
          first_stmt[2] == :instrumented)
    rescue MethodSource::SourceNotFoundError
      return nil
    end

    def initialize(instrument_domain = nil)
      @instrument_domain = instrument_domain
      @replacers = []
      @stack_depth = 0

      # mark the instrumentation
      replace :defn do |sexp|
        mark_sexp_instrumented sexp
      end

      # make sure the instrumentation propagates through calls
      replace :call do |sexp|
        # expected format: s(:call, object, method_name, *args)
        # replaced with Extract::Instrumenter.e(instrumenter_id, object, method_name, *args)
        original_object = sexp.sexp_body[0] || s(:self)
        original_method_name = sexp.sexp_body[1]
        original_args = sexp.sexp_body[2..-1]
        s(:call, Instrumenter.sexp_class_rep, :e, original_object, s(:lit, original_method_name), *original_args)
      end
    end

    def should_instrument?(object, method_name)
      method = object.method method_name
      return false if method.source_location.nil?
      return true if @instrument_domain.nil? || method.source_location =~ /^#{@instrument_domain}.*$/
      source = method.source
      sexp = ruby_parser.process source
      !sexp_instrumented? sexp
    rescue
      raise
    end

    def replace(type, &block)
      @replacers << [type, block]
    end

    def self.e(object, method_name, *args, &block)
      Instrumenter.get_instance.execute_instrumented object, method_name, *args, &block
    end

    def execute_instrumented(object, method_name, *args, &block)
      self.exec_within do
        instrument object, method_name
        return object.send method_name, *args, &block
      end
    end

    def instrument(object, method_name)
      if should_instrument? object, method_name
        begin
          method = object.method method_name
          source = method.source

          # Ruby 2.0.0 support is in development as of writing this
          sexp = ruby_parser.process source

          instrumented_sexp = instrument_sexp sexp

          new_code = Ruby2Ruby.new.process instrumented_sexp

          object.replace_method method_name, new_code

          return new_code
        rescue MethodSource::SourceNotFoundError
        end
      end
    end

    def instrument_sexp(sexp)
      @replacers.reverse_each do |type, block|
        sexp = sexp.block_replace type, &block
      end
      sexp
    end
  end
end
