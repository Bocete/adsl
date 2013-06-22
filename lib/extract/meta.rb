require 'rubygems'
require 'backports'

class Object
  def replace_method(method_name, source)
    raise "Object #{self} of class #{self.class} does not respond to #{method_name}" unless self.respond_to? method_name, true

    im = self.singleton_class.instance_method(method_name)
    owner = im.owner
    owner.class_eval source

    true
  end
end
