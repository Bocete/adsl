require 'sexp_processor'

class Sexp
  def block_replace(search_type, &block)
    new = self.map do |element|
      if element.is_a? Sexp
        element.block_replace search_type, &block
      else
        element
      end
    end
    result = Sexp.from_array new
    result = block[result] if result.sexp_type == search_type
    return result
  end
end
