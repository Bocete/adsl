require 'tempfile'
require 'adsl/prover/spass/fol_extensions'

module ADSL
  module Prover
    module Spass
      module EngineExtensions

        attr_accessor :spass_temp_file, :spass_code, :spass_force_sorts
        
        def _prepare_spass
          @spass_temp_file = Tempfile.new 'ADSL_spass'
          @spass_code = @fol.to_spass_string
          @spass_temp_file.write @spass_code
          @spass_temp_file.close
          if @spass_args
            arg_combos = [@spass_args]
          else 
            arg_combos = ["", "-Sorts=0"]
          end
          arg_combos.map{ |a| "SPASS #{a} -TimeLimit=#{@options[:timeout]} #{@spass_temp_file.path}" }
        end

        def _set_spass_args(args = nil)
          @spass_args = args if args.present?
        end

        def _analyze_spass_output(output)
          result = {}

          predicates = /predicates\s*\[([^\]]*)\]/.match(@spass_code)
          result[:predicate_count] = predicates.nil? ? 0 : predicates[1].scan(/\w+/).length
          
          sorts = /sorts\s*\[([^\]]*)\]/.match(@spass_code)
          result[:sort_count] = sorts.nil? ? 0 : sorts[1].scan(/\w+/).length
    
          formulae = @spass_code.scan(/formula\s*\([^\.]+\)\./)
          result[:formula_count] = formulae.length
          result[:average_formula_length] = formulae.map(&:length).sum / formulae.length
    
          times = output.scan(/(\d+):(\d+):(\d+)\.(\d+)/)
          
          raise "Incorrect time format extracted from spass output. Tail of spass output: #{output}" if times.length != 6

          times = times.map{ |time| time[3].to_f/100 + time[2].to_i + time[1].to_i*60 + time[0].to_i*60*60 }
          
          result[:total_time] = times.first.seconds
          #result[:spass_preparation_time] = times[1..2].sum.seconds
          #result[:spass_proof_lookup_time] = times[3..5].sum.seconds
    
          #result[:proof_clause_count] = /^SPASS derived (\d+) clauses.*$/.match(output)[1].to_i
          
          result[:memory] = /^\s*SPASS allocated (\d+) KBytes.*$/.match(output)[1].to_i
          result[:steps] = /^\s*SPASS derived (\d+) clauses,.*$/.match(output)[1].to_i
  
          result_line = /^SPASS beiseite: (.+)\.$/.match(output)[1]
          case result_line
          when 'Proof found'
            result[:result] = :correct
          when 'Completion found'
            result[:result] = :incorrect
          else
            result[:result] = :timeout
          end

          result[:input] = @spass_code
          result[:output] = output

          result
        end

        def _cleanup_spass
          @spass_code = nil
          @spass_temp_file.unlink unless @spass_temp_file.nil?
          @spass_temp_file = nil
        end

      end
    end
  end
end
