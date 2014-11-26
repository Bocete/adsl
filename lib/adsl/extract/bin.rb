require 'adsl/extract/rails/rails_extractor'

module ADSL
  module Extract
    module Bin

      def extract_ast(options = {})
        options = {
          :verify_options => {},
          :extract_options => {}
        }.merge options
        ast = options[:ast]
        ast = ADSL::Extract::Rails::RailsExtractor.new(options[:extract_options]).adsl_ast if ast.nil?
        ast
      end

      def verify_spass(options = {})
        ast = extract_ast options
        
        require 'adsl/spass/bin'
        self.class.send :include, ::ADSL::Spass::Bin

        return verify(ast, options[:verify_options])
      end

      def adsl_translate(options = {})
        ast = extract_ast options
        puts ast.to_adsl
      end

    end
  end
end
