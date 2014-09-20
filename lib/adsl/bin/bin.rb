require 'active_support/core_ext/numeric/time'
require 'optparse'
require 'colorize'
require 'set'
require 'adsl/parser/adsl_parser'
require 'adsl/prover/engine'
require 'adsl/translation/ds_extensions'
require 'adsl/util/csv_hash_formatter'

module ADSL
  module Bin
    class Bin
      DEFAULT_OPTS = {
        :input => 'stdin'
        :prover => 'all',
        :halt_on_error => true,
        :check_satisfiability => true,
        :timeout => 1.minute,
        :output => 'text',
        :actions => nil,
        :invariants => nil,
        :translate => false
      }

      attr_accessor :ds

      def initialize(options={})
        @options = Bin::DEFAULT_OPTS.merge options
        if Set[*options.keys] > Set[*Bin::DEFAULT_OPTS.keys]
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
        
        @ds = adsl.typecheck_and_resolve
        @ds
      end

      def filter_list(list, filters)
        return list if filters.empty?
        filters.map{ |f| list.select{ |l| l.name =~ /#{f}/} }.map{ |a| Set[*a] }.inject(&:+)
      end

      def gen_tasks
        actions    = filter_list @ds.actions,    @options[:actions]
        invariants = filter_list @ds.invariants, @options[:invariants]
        tasks = []
        actions.each do |a|
          if @options[:check_satisfiability]
            tasks << [a, nil]
          end
          tasks += invariants.map{ |i| [a, i] }
        end
        tasks
      end

      def output(result, action, invariant)
        if options[:output] == 'text'
          if invariant.nil?
            # sat check, expected to fail
            result_string = case result[:result]
            when :correct
              "failed".red
            when :incorrect
              "passed".green
            when :timeout
              "timed out".yellow
            when :inconclusive
              "inconclusive".yellow
            else
              raise "Unknown verification result #{result[:result]}"
            end
            puts "Satisfiability check of action #{action.name} #{result_string}"
          else
            # sat check, expected to fail
            puts case result[:result]
            when :correct
              "Action #{action.name} #{"preserves".green} invariant #{invariant.name}"
            when :incorrect
              "Action #{action.name} #{"may break".red} invariant #{invariant.name}"
            when :timeout
              "Verification of action #{action.name} and invariant #{invariant.name} #{"timed out".yellow}"
            when :inconclusive
              "#{"Inconclusive".yellow} result on action #{action.name} and invariant #{invariant.name}"
            else
              raise "Unknown verification result #{result[:result]}"
            end
          end
        elsif options[:output] == 'csv'
          @csv_output ||= ADSL::Util::CSVHashFormatter.new
          @csv_output << result
        elsif options[:output] == 'silent'
        else
          raise "Unknown verification output #{options[:output]}"
        end
      end

      def finalize_output
        puts @csv_output if @csv_output
      end

      def translate
        tasks = gen_tasks
        
        tasks.each do |action, invariant|
          fol = @ds.translate_action action.name, invariant
          provers.each do |p|
            puts fol.send "to_#{p}_string"
            puts
          end
        end
      end

      def verify
        tasks = gen_tasks

        tasks.each do |action, invariant|
          inv = invariant.nil? ? false, invariant
          fol = @ds.translate_action action.name, inv
          engine = ADSL::Prover::Engine.new *provers, fol, @options
          result = engine.verify
          output result, action, invariant
          if @options[:halt_on_error]
            failed = invariant.nil? ? (result[:result] == :correct) : (result[:result] == :incorrect)
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
