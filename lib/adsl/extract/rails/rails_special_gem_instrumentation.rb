require 'adsl/extract/rails/other_meta'

module ADSL
  module Extract
    module Rails
      module RailsSpecialGemInstrumentation

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

            if cancan_exists?
              current_user_code = <<-RUBY.strip
                #{role_class}.new(:adsl_ast => ADSL::Parser::ASTCurrentUser.new)
              RUBY
            else
              current_user_code = <<-RUBY.strip
                #{role_class}.find(-1)
              RUBY
            end

            controller_class.class_eval <<-ruby
              def authenticate_#{role}!(*args); end
              def #{role}_signed_in?(*args); true; end
              def current_#{role}(*args); #{ current_user_code }; end
              def #{role}_session(*args); ::ADSL::Extract::MetaUnknown.new; end
              def only_render_implemented_actions(*args); end
            ruby
          end
        end

        def instrument_gem_paperclip(controller_class, action)
          return unless Object.lookup_const('Paperclip')

          Paperclip::Attachment.class_exec do
            def initialize(*args); end
            def assign(*args); end
          end
        end

        def instrument_gems(controller_class, action)
          instrument_gem_ransack controller_class, action
          instrument_gem_authlogic controller_class, action
          instrument_gem_devise controller_class, action
          instrument_gem_paperclip controller_class, action
        end

      end
    end
  end
end
