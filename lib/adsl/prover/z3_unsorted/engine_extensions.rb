require 'tempfile'
require 'adsl/prover/z3_unsorted/fol_extensions'

module ADSL
  module Prover
    module Z3Unsorted
      module EngineExtensions

        attr_accessor :smt2_unsorted_temp_file, :smt2_unsorted_code
        
        def _prepare_z3_unsorted
          @smt2_unsorted_temp_file = Tempfile.new 'ADSL_smt2'
          @smt2_unsorted_code = @fol.to_smt2_unsorted_string
          @smt2_unsorted_temp_file.write @smt2_unsorted_code
          @smt2_unsorted_temp_file.close
          ["z3 -smt2 -st -T:#{@options[:timeout]} #{@smt2_unsorted_temp_file.path}" ]
        end

        def _analyze_z3_unsorted_output(output)
          result = {}

          result[:predicate_count] = @smt2_unsorted_code.scan(/^\(declare\-fun.*Bool\)$/).length
          result[:sort_count]      = @smt2_unsorted_code.scan(/^\(declare\-sort.*\)$/).length
    
          formulae = @smt2_unsorted_code.scan(/^\(assert.*\)$/)
          result[:formula_count] = formulae.length
          result[:average_formula_length] = formulae.map(&:length).sum / formulae.length
  
          temp = output.scan(/\(((?::[\w\-]+\s+\d+(?:\.\d+)?\s*)+)\)/)
          stat_string = temp[0][0]
          stats = Hash[*stat_string.split(/\s+/)]
          result[:total_time] = (stats[':total-time'] || stats[':time']).to_f.seconds
          result[:memory] = stats[':memory'].to_f * 1024 # mb to kb
          result[:steps] = stats[':added-eqs'].to_i

          first_line = output.match /^\w+$/
          case first_line.to_s
          when 'unsat'
            result[:result] = :correct
          when 'sat'
            result[:result] = :incorrect
          else
            result[:result] = :timeout
          end

          result[:input] = @smt_unsorted_code
          result[:output] = output

          result
        end

        def _cleanup_z3_unsorted
          @smt2_unsorted_code = nil
          @smt2_unsorted_temp_file.unlink unless @smt2_unsorted_temp_file.nil?
          @smt2_unsorted_temp_file = nil
        end

      end
    end
  end
end
