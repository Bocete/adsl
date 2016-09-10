require 'active_support/core_ext/numeric/time'
require 'optparse'
require 'colorize'
require 'set'
require 'adsl/lang/parser/adsl_parser.tab'
require 'adsl/prover/engine'
require 'adsl/ds/fol_translation/ds_extensions'
require 'adsl/util/csv_hash_formatter'

module ADSL
  module Bin
    class Bin
      DEFAULT_OPTS = {
        :input => 'stdin',
        :prover => 'all',
        :prover_args => nil,
        :halt_on_error => false,
        :timeout => 1.minute,
        :output => 'text',
        :actions => nil,
        :invariants => nil,
        :ac => true,
        :translate => false
      }

      attr_accessor :ds

      def initialize(options={})
        @options = Bin::DEFAULT_OPTS.merge options
        unless Set[*options.keys].subset? Set[*Bin::DEFAULT_OPTS.keys]
          raise OptionParser::InvalidArgument, "Unknown option(s) #{Set[*options.keys] - Set[*Bin::DEFAULT_OPTS.keys]}"
        end
      end

      def provers
        @options[:prover] == 'all' ? ['spass', 'z3'] : [@options[:prover]]
      end

      def input_ds
        return @ds unless @ds.nil?

        if @options[:input] != 'stdin'
          path = @options[:input]
          raise OptionParser::InvalidArgument, "File not found: #{File.expand_path path}" unless File.file? path
          adsl = File.read path
        else
          adsl = STDIN.read
        end

        @ds = ADSL::Lang::Parser::ADSLParser.new.parse adsl
        @ds
      end

      def filter_list(list, filters)
        return list if filters.nil? || filters.empty?
        list.select{ |l| filters.include? l.name.to_s }
      end

      def gen_problems
        actions              = filter_list @ds.actions,    @options[:actions]
        invariants           = filter_list @ds.invariants, @options[:invariants]
        check_access_control = @options[:ac]

        problems = []

        actions.each do |action|
          problems += @ds.generate_problems(action.name, invariants, check_access_control).map{ |p| [action, p] }
        end

        problems
      end

      def output(result, action, problem)
        if @options[:output] == 'text'
          puts case result[:result]
          when :correct
            "Action #{action.name} #{"passes".green} verification for problem #{problem.name}"
          when :incorrect
            "Action #{action.name} #{"fails".red} verification for problem #{problem.name}"
          when :timeout
            "Verification of action #{action.name} and problem #{problem.name} #{"timed out".yellow}"
          when :inconclusive
            "#{"Inconclusive".yellow} result on action #{action.name} and problem #{problem.name}"
          else
            raise "Unknown verification result #{result[:result]}"
          end
        elsif @options[:output] == 'csv'
          @csv_output ||= ADSL::Util::CSVHashFormatter.new(:action, :problem, :prover)

          result.reject!{ |key, val| [:input, :output].include? key }
          result[:action] = action.name
          result[:problem] = problem.name

          @csv_output << result 
        elsif @options[:output] == 'silent'
        else
          raise "Unknown verification output #{ @options[:output] }"
        end
      end

      def finalize_output
        puts @csv_output if @csv_output
      end

      def translate
        @ds = input_ds
        problems = gen_problems

        provers.each do |p|
          ADSL::Prover::Engine.load_engine p
        end
        
        problems.each do |action, problem|
          translation = @ds.translate_action action.name, problem
          fol = translation.to_fol
          provers.each do |p|
            lang = p.to_s == 'spass' ? 'spass' : 'smt2'
            puts fol.send "to_#{ lang }_string"
            puts
          end
        end
      end

      def verify
        @ds = input_ds
        problems = gen_problems

        problems.each do |action, problem|
          translation = @ds.translate_action action.name, problem
          fol = translation.to_fol
          engine = ADSL::Prover::Engine.new provers, fol, @options
          engine.set_prover_args @options[:prover_args] if @options[:prover_args].present?
          result = engine.verify
          output result, action, problem
          if @options[:halt_on_error]
            failed = problem.nil? ? (result[:result] == :correct) : (result[:result] == :incorrect)
            return if failed
          end
        end
      ensure
        finalize_output
      end

      def run
        @options[:translate] ? translate : verify
      end

    end
  end
end
