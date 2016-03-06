
module ADSL
  module Lang
   
    class ASTNode
      def self.node_fields(*fields)
        container_for *(fields + [:lineno])
        recursively_comparable
      end

      def block_replace(&block)
        to_h.each do |name, value|
          new_value = if value.is_a? Array
            value.map do |e|
              new_e = e.respond_to?(:block_replace) ? e.block_replace(&block) : e
            end
          elsif value.is_a? ASTNode
            new_value = value.block_replace(&block) || value
          else
            value.dup
          end
          send "#{name}=", new_value
        end
        block[self] || self
      end

      def preorder_traverse(&block)
        children.each do |child|
          child.preorder_traverse &block if child.respond_to? :preorder_traverse
        end
        block[self]
      end

      # used for statistics
      def adsl_ast_size
        sum = 1
        self.class.container_for_fields.each do |field_name|
          field = send field_name
          if field.is_a? Array
            field.flatten.each do |subfield|
              sum += subfield.adsl_ast_size if subfield.respond_to? :adsl_ast_size
            end
          else
            sum += field.adsl_ast_size if field.respond_to? :adsl_ast_size
          end
        end
        sum
      end
    end

  end
end

