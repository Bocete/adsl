require 'active_support/concern'

module ADSL
  module Extract
    module Rails
      module ActiveRecordMetaclassLookups

        extend ActiveSupport::Concern

          def method_missing(method, *args, &block)
            return self.find if method.to_s.start_with? 'find_by_'
            super
          end

          def respond_to?(method, *args, &block)
            return true if method.to_s.start_with? 'find_by_'
            super
          end
      end
    end
  end
end
