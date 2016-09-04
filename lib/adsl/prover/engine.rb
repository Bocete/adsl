require 'adsl/prover/util'

module ADSL
  module Prover
    class Engine

      attr_reader :fol, :commands, :provers

      def self.load_engine(prover)
        require "adsl/prover/#{prover}/engine_extensions"
        Engine.send :include, ADSL::Prover.lookup_const("#{prover.to_s.camelize}::EngineExtensions")
      end

      def set_prover_args(args)
        @provers.each do |prover|
          self.send "_set_#{ prover }_args", args if args.present?
        end
      end

      def initialize(provers, fol, options={})
        @provers = provers.respond_to?(:each) ? provers : [provers]
        @fol = fol
        @options = {
          :timeout => 1.minute,
          :skip_stats => false
        }.merge options

        @provers.each do |prover|
          Engine.load_engine prover
        end
      end

      def prepare_prover_commands
        @commands = []
        @provers.each do |prover|
          @commands += self.send("_prepare_#{prover}").map{ |c| [c, prover] }
        end 
      end
      
      def run
        output, index = ADSL::Prover::Util.process_race(*@commands.map(&:first))
        result = self.send "_analyze_#{commands[index][1]}_output", output
        result[:prover] = commands[index][1]
        result
      end

      def cleanup
        @provers.each do |prover|
          self.send "_cleanup_#{prover}"
        end
      end

      def verify
        prepare_prover_commands
        return run
      ensure
        cleanup
      end
      
    end
  end
end
