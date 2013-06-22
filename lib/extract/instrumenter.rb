require 'backports'
require 'sexp_processor'
require 'extract/sexp_utils'
require 'extract/meta'
require 'ruby_parser'
require 'method_source'
require 'ruby2ruby'

module Extract
  class Instrumenter
    @instances = {}

    def self.get_instance(id)
      @instances[id]
    end

    def self.sexp_class_rep
      s(:colon2, s(:const, :Extract), :Instrumenter)
    end

    def ruby_parser
      RUBY_VERSION >= '2' ? Ruby19Parser.new : RubyParser.for_current_ruby
    end

    def self.instrumented_by(*ids)
      # a dummy method injected into the AST
    end

    def mark_sexp_instrumented(sexp)
      raise 'Already instrumented' if sexp_instrumented? sexp
      
      first_stmt = sexp[3]

      if first_stmt[0] != :call or
          first_stmt[1] != Instrumenter.sexp_class_rep or
          first_stmt[2] != :instrumented_by
        new_stmt = s(:call, Instrumenter.sexp_class_rep, :instrumented_by, s(:lit, self.object_id))
        sexp.insert 3, new_stmt
        sexp.insert 4, s(:call, nil, :require, s(:str, 'extract/instrumenter'))
      else
        first_stmt << s(:lit, self.object_id) 
      end
      sexp
    end

    def sexp_instrumented?(sexp)
      first_stmt = sexp[3]
      return false if first_stmt[0] != :call or
          first_stmt[1] != Instrumenter.sexp_class_rep or
          first_stmt[2] != :instrumented_by

      ids = first_stmt[3..-1].map{ |lit_sexp| lit_sexp[1] }
      return ids.include? self.object_id
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
        # replaced with Extract::Instrumenter.get_instance(id).execute_instrumented(object, method_name, *args)
        original_object = sexp.sexp_body[0] || s(:self)
        original_method_name = sexp.sexp_body[1]
        original_args = sexp.sexp_body[2..-1]
        instrumenter_sexp = s(:call, Instrumenter.sexp_class_rep, :get_instance, s(:lit, self.object_id))
        s(:call, instrumenter_sexp, :execute_instrumented, original_object, s(:lit, original_method_name), *original_args)
      end
    end

    def should_instrument?(object, method_name)
      method = object.method method_name
      return true if @instrument_domain.nil? || method.source_location =~ /^#{@instrument_domain}.*$/
      source = method.source
      sexp = ruby_parser.process source
      !sexp_instrumented? sexp
    end

    def replace(type, &block)
      @replacers << [type, block]
    end

    def execute_instrumented(object, method_name, *args, &block)
      self.class.instance_variable_get(:@instances)[self.object_id] = self if @stack_depth == 0
      @stack_depth += 1

      if should_instrument? object, method_name
        begin
          method = object.method method_name
          source = method.source

          # Ruby 2.0.0 support is in development as of writing this
          sexp = ruby_parser.process source

          instrumented_sexp = instrument sexp

          new_code = Ruby2Ruby.new.process instrumented_sexp

          object.replace_method method_name, new_code
        rescue MethodSource::SourceNotFoundError
        end
      end

      object.send method_name, *args, &block
    ensure
      @stack_depth -= 1
      self.class.instance_variable_get(:@instances)[self.object_id] = nil if @stack_depth == 0
    end

    def instrument(sexp)
      @replacers.reverse_each do |type, block|
        sexp = sexp.block_replace type, &block
      end
      sexp
    end
  end
end
