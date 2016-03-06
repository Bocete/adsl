require 'adsl/util/container'

module ADSL
  module DS
    module FOLTranslation
 
     class TypedString
       container_for :sort, :str
       recursively_comparable
 
       def initialize(sort, str)
         raise ArgumentError, "Invalid sort `#{sort}`" unless sort.is_a? ADSL::FOL::Sort
         @sort = sort
         @str = str.to_s
       end
 
       def to_sort
         @sort
       end
 
       def unroll
         [@sort, @str]
       end
 
       # for FOL
       def optimize
         self
       end
 
       alias_method :name, :str
       alias_method :to_s, :str
     end
 
   end
 end
end
