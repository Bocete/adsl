module ADSL
  module Util
    module PartialOrdered
      def >=(other); ((result = compare(other)) && result >= 0) || false; end
      def >(other);  ((result = compare(other)) && result >  0) || false; end
      def <(other);  ((result = compare(other)) && result <  0) || false; end
      def <=(other); ((result = compare(other)) && result <= 0) || false; end
    end
  end
end
