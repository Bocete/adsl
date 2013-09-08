require 'adsl/extract/rails/other_meta'

module ADSL
  module Extract
    module Rails
      module RailsSpecialGemInstrumentation

        def instrument_gem_cancan(controller_class, action)
          return unless klass = Object.lookup_const('CanCan::ControllerResource')

          model_class_name = controller_class.controller_name.singularize.camelize
          klass.class_eval <<-ruby, __FILE__, __LINE__
            def name_from_controller
              "#{ model_class_name.underscore.singularize }"
            end

            def namespace
              [#{ model_class_name.split('::')[0..-2].map{ |a| "'#{a}'" }.join(', ') }]
            end

            def authorize_resource; end

            def find_resource
              #{ model_class_name }.find
            end

            def build_resource
              #{ model_class_name }.new
            end

            def load_collection
              #{ model_class_name }.where
            end

            def load_resource
              unless skip?(:load)
                var_name, objset = if load_instance?
                  [instance_name.to_s, load_resource_instance]
                else
                  [instance_name.to_s.pluralize, load_collection]
                end
                ins_explore_all 'load_resource' do
                  ins_stmt(ADSL::Parser::ASTAssignment.new(
                    :var_name => ADSL::Parser::ASTIdent.new(:text => "at__\#{var_name}"),
                    :objset => objset.adsl_ast
                  ))
                  nil
                end
                @controller.instance_variable_set(
                  "@\#{ var_name }",
                  #{ model_class_name }.new(:adsl_ast => ADSL::Parser::ASTVariable.new(
                    :var_name => ADSL::Parser::ASTIdent.new(:text => "at__\#{var_name}")
                  ))
                )
              end
            end
          ruby

          controller_class.class_exec do
            def authorize!(*args); end
          end

        end

        def instrument_gem_ransack(controller_class, action)
          if Object.lookup_const('RansackUI')
            Object.lookup_const('RansackUI::ControllerHelpers').class_exec do
              def load_ransack_search(*args); end
            end
          end

          if Object.lookup_const('Ransack')
            ActiveRecord::Base.class_exec do
              def search(*args); where; end
            end
          end
        end

        def instrument_gem_authlogic(controller_class, action)
          return unless Object.lookup_const('Authlogic')

          # only instrument this if there is a class called User; assume that a user is the logged in entity
          return unless Object.lookup_const('User')

          Object.lookup_const('Authlogic::Session::Base').class_exec do
            def self.find(*args)
              ADSL::Extract::Rails::PartiallyUnknownHash.new(
                :record => User.find
              )
            end
          end
        end

        def instrument_gem_devise(controller_class, action)
          return unless Object.lookup_const('Devise')
          
          Devise.mappings.values.each do |mapping|
            role = mapping.singular
            role_class = mapping.class_name
            controller_class.class_eval <<-ruby
              def authenticate_#{role}!(*args); end
              def #{role}_signed_in?(*args); true; end
              def current_#{role}(*args); #{role_class}.find(-1); end
              def #{role}_session(*args); ::ADSL::Extract::MetaUnknown.new; end
              def only_render_implemented_actions(*args); end
            ruby
          end
        end

        def instrument_gems(controller_class, action)
          instrument_gem_cancan controller_class, action
          instrument_gem_ransack controller_class, action
          instrument_gem_authlogic controller_class, action
          instrument_gem_devise controller_class, action
        end

      end
    end
  end
end
