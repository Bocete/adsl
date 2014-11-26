module ADSL
  module Util
    module PartialOrdered
      [:>=, :>, :<, :<=].each do |operator|
        self.send :define_method, operator do |other|
          result = compare other
          return false if result.nil? # nil and false are treated the same
          result.send operator, 0
        end
      end
    end
  end
end
