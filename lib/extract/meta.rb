require 'backports'

class Class
  def inheritance_chain
    chain = []
    klass = self
    until klass.nil?
      chain << klass
      klass = klass.superclass
    end
    chain.reverse!
  end
end

class Object
  def replace_method(method, source)
    raise "Object #{self} of class #{self.class} does not respond to #{method}" unless self.respond_to? method, true

    classes = [self.singleton_class] + self.class.inheritance_chain.reverse

    classes.each do |klass|
      klass_plus_modules = [klass] + klass.included_modules
      klass_plus_modules.each do |klass_or_module|
        im = klass_or_module.instance_methods false
        next unless im.include?(method.to_s) or im.include?(method.to_sym)
        
        klass_or_module.class_eval source
        return true
      end
    end
    raise 'should never reach this'
  end
end
