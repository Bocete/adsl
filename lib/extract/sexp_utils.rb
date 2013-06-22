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

  def find_shallowest(search_type)
    return [self] if sexp_type == search_type
    self.inject([]) do |collection, subsexp|
      collection << subsexp.find_shallowest(search_type) if subsexp.is_a?(Sexp)
      collection
    end.flatten(1)
  end
end
