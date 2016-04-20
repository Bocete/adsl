require 'adsl/extract/rails/rails_extractor'
require 'adsl/ds/fol_translation/ds_extensions'
require 'adsl/prover/engine'

module ADSL
  module Extract
    module Bin

      def extract_ast(options = {})
        options = {
          :verify_options => {},
          :extract_options => {}
        }.merge options
        ast = options[:ast]
        if ast.nil?
          extractor = ADSL::Extract::Rails::RailsExtractor.new(options[:extract_options])
          extractor.extract_all_actions
          ast = extractor.adsl_ast
        end
        ast
      end

      def to_fol(ast, options)
        action_name = nil
        action_name = options[:verify_options][:action].to_s
        action_name = ast.actions.first.name if ast.actions.length == 1
        raise "Action name undefined" if action_name.nil? || action_name.empty?

        ds_spec = ast.typecheck_and_resolve
        problems = ds_spec.generate_problems action_name
        ds_spec.translate_action(action_name, *problems).to_fol
      end

      def verify(options = {})
        ast = extract_ast options
        fol = to_fol ast, options
        
        engine = ADSL::Prover::Engine.new [:spass, :z3], fol, options[:verify_options]

        result = engine.verify
        return result[:result] == :correct
      end

      def adsl_translate(options = {})
        ast = extract_ast options
        puts ast.to_adsl
      end

    end
  end
end
