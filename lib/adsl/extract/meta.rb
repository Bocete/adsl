require 'rubygems'
require 'backports'

class Object
  def replace_method(method_name, source = nil, &block)
    unless self.respond_to? method_name, true
      raise ArgumentError, "Object #{self} of class #{self.class} does not respond to #{method_name}"
    end
    
    im = self.singleton_class.instance_method(method_name)
    
    aliases = []
    self.singleton_class.instance_methods.each do |other_name|
      next if other_name == method_name
      other = self.singleton_class.instance_method other_name
      aliases << [other_name, other] if other == im
    end

    owner = im.owner

    unless source.nil?
      owner.class_eval source
    else
      owner.send :define_method, method_name, &block
    end

    aliases.each do |other_name, other|
      other.owner.class_exec do
        alias_method other_name, method_name
      end
    end

    true
  end
end
