require 'adsl/extract/rails/rails_extractor'

module ADSL
  module Verification
    module RailsVerification

      def extract_ast(options = {})
      end

      def verify_spass(options = {})
        ast = extract_ast options
        spec = ast.typecheck_and_resolve
        
        require 'adsl/spass/bin'
        self.class.send :include, ::ADSL::Spass::Bin

        return verify(spec, options[:verify_options])
      end

      def extract_ast(options = {})
        options = {
          :verify_options => {},
          :extract_options => {}
        }.merge options
        ast = options[:ast]
        ast = ADSL::Extract::Rails::RailsExtractor.new(options[:extract_options]).adsl_ast if ast.nil?
        ast
      end

      def adsl_translate(options = {})
        ast = extract_ast options
        puts ast.to_adsl
      end

    end
  end
end
