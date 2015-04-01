require 'adsl/util/general'

module ADSL
  module Util
    module Container
      
      def initialize(args = {})
        args = args.empty? ? {} : args
        args ||= {}
   
        all_fields = self.class.container_for_fields

        all_fields.each do |field|
          instance_variable_set "@#{field}".to_sym, args.delete(field.to_sym)
        end

        if not args.empty?
          raise ArgumentError, "Undefined fields mentioned in initializer of #{self.class}: #{args.keys.map{ |key| ":#{key}"}.join(", ")}" + "\n[#{all_fields.to_a.join ' ' }]"
        end

        self
      end
    
      def recursively_gather
        raise "Recursively gather requires a block" unless block_given?
        to_inspect = [self]
        inspected = []
        while not to_inspect.empty?
          elem = to_inspect.pop
          inspected << elem
          if elem.class.respond_to? :container_for_fields
            elem.class.container_for_fields.each do |field|
              field_val = elem.send(field)
              next if field_val.nil?
              [field_val].flatten.each do |subval|
                to_inspect << subval unless inspected.include?(subval)
              end
            end
          end
        end
        result = inspected.map do |val|
          yield val
        end
        [*result.flatten.compact]
      end
      
      # block should return true if this is to be selected
      # nil if not but the algorithm should descend
      # false otherwise: neither select or recursively descend further
      def recursively_select(&block)
        selection = []
        self.class.container_for_fields.each do |field_name|
          field = send field_name
          subfields = field.is_a?(Array) ? field.flatten : [field]
          subfields.each do |field|
            progress = block[field]
            case progress
            when true
              selection << field
              selection += field.recursively_select &block if field.respond_to? :recursively_select
            when nil
              selection += field.recursively_select &block if field.respond_to? :recursively_select
            else
            end
          end
        end
        selection
      end

      module ClassMethods
        def recursively_comparable
          self.class_exec do
            include RecursivelyComparable
          end
        end
      end

      module RecursivelyComparable
        def eql?(other)
          return false if other.class != self.class
          self.class.container_for_fields.each do |field|
            f1 = self.send field
            f2 = other.send field
            if f1.respond_to?(:each) && f2.respond_to?(:each)
              return false if f1.count != f2.count
              f1.zip(f2).each do |e1, e2|
                return false unless f1.eql? f2
              end
            else
              return false unless f1.eql? f2
            end
          end
          return true
        end
        alias_method :==, :eql?
        
        def hash
          [*self.class.container_for_fields.map{ |f| self.send f }].hash
        end
        
        def dup
          new_values = {}
          self.class.container_for_fields.each do |field_name|
            value = send field_name
            new_values[field_name] = value.deep_dup
          end
          self.class.new new_values
        end
      end

    end
  end
end

class Module
  def container_for(*fields)
    all_fields = Set.new(fields)
    if respond_to? :container_for_fields
      prev_fields = send :container_for_fields
      all_fields.merge prev_fields
    end
    singleton_class.send :define_method, :container_for_fields, lambda{ all_fields }

    self.class_eval do
      attr_accessor *all_fields
    end

    self.include ADSL::Util::Container
    self.extend ADSL::Util::Container::ClassMethods
  end
end
