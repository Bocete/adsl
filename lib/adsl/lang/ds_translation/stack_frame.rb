module ADSL
  module Lang
    module DSTranslation
      class StackFrame < ActiveSupport::OrderedHash
        attr_accessor :var_write_listeners
        attr_accessor :var_read_listeners
        attr_accessor :ds_statements
        
        def initialize
          super
          @var_write_listeners = []
          @var_read_listeners = []
          @ds_statements = []
        end
      
        def on_var_read(&block)
          listeners = @var_read_listeners
          listeners.push block
        end
        
        def on_var_write(&block)
          listeners = @var_write_listeners
          listeners.push block
        end
  
        def fire_write_event(name)
          listeners = @var_write_listeners
          listeners.each do |listener|
            listener.call name
          end
        end
        
        def fire_read_event(name)
          listeners = @var_read_listeners
          listeners.each do |listener|
            listener.call name
          end
        end
  
        def dup
          other = StackFrame.new
          self.each do |key, val|
            other[key] = val.dup
          end
          other.var_write_listeners = @var_write_listeners.dup
          other.var_read_listeners = @var_read_listeners.dup
          other.ds_statements = @ds_statements.dup
          other
        end
  
        def clone
          dup
        end

      end
    end
  end
end

