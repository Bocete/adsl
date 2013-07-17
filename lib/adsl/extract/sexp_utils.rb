require 'sexp_processor'

class Sexp
  def block_replace(*search_types, &block)
    new = self.map do |element|
      if element.is_a? Sexp
        result = element.block_replace *search_types, &block
        result = [result] unless result.class == Array
        result
      else
        [element]
      end
    end
    result = Sexp.from_array new.flatten(1)
    result = block[result] if search_types.include? result.sexp_type
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

class Module
  def to_sexp
    parts = self.name.split('::')
    sexp = s(:colon3, parts.shift.to_sym)
    parts.each do |part|
      sexp = s(:colon2, sexp, part.to_sym)
    end
    sexp
  end
end
