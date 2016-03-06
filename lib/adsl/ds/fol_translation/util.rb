require 'adsl/fol/first_order_logic'

module ADSL
  module DS
    module FOLTranslation
      class Util
        include ADSL::FOL
  
        def self.gen_formula_for_unique_arg(pred, *args)
          individuals = []
          args.each do |arg|
            arg = arg.is_a?(Range) ? arg.to_a : [arg].flatten
            next if arg.empty?
            vars1 = pred.arity.times.map{ |i| TypedString.new pred.sorts[i], "e#{i+1}" }
            vars2 = vars1.dup
            as = []
            bs = []
            arg.each do |index|
              a = TypedString.new pred.sorts[index], "a#{index+1}"
              vars1[index] = a
              b = TypedString.new pred.sorts[index], "b#{index+1}"
              vars2[index] = b
              as << a
              bs << b
            end
            individuals << ForAll.new((vars1 | vars2).map(&:unroll), Implies.new(
              And.new(pred[vars1], pred[vars2]),
              PairwiseEqual.new(as, bs)
            ))
          end
          And.new(*individuals).optimize
        end
  
      end
    end
  end
end

