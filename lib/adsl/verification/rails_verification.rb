require 'adsl/extract/rails/rails_extractor'

module ADSL
  module Verification
    module RailsVerification

      def extract_ast(options = {})
        ADSL::Extract::Rails::RailsExtractor.new(options).adsl_ast
      end

      def verify_spass(options = {})
        options = {
          :verify_options => {},
          :extract_options => {}
        }.merge options
        ast = options[:ast]
        ast = extract_ast(options[:extract_options]) if ast.nil?

        spec = ast.typecheck_and_resolve
        
        require 'adsl/spass/bin'
        self.class.send :include, ::ADSL::Spass::Bin

        return verify(spec, options[:verify_options])
      end

    end
  end
end
