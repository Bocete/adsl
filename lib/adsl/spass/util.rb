module ADSL
  module Spass
    module Util
      def replace_conjecture(input, conjecture)
        input.gsub(/list_of_formulae\s*\(\s*conjectures\s*\)\s*\..*?end_of_list\./m, <<-SPASS)
        list_of_formulae(conjectures).
          formula(#{conjecture.resolve_spass}).
        end_of_list.
        SPASS
      end
    end
  end
end
