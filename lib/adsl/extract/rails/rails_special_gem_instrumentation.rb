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

        def devise_exists?
          Object.lookup_const('Devise')
        end

        def instrument_gem_devise(controller_class, action)
          return unless devise_exists?

          roles = []
          Devise.mappings.values.each do |mapping|
            role = mapping.singular
            role_class = mapping.class_name
            roles << [role, role_class]
          end

          if roles.empty? && Object.lookup_const(:User)
            roles << ['user', 'User']
          end

          Devise::Models::Trackable.class_exec do
            def update_tracked_fields!(*args)
            end
          end

          Devise::Models::DatabaseAuthenticatable.class_exec do
            def valid_password?(*args)
              ADSL::Lang::ASTBoolean.new
            end

            def password_digest(*args)
              #ADSL::Extract::Rails::UnknownOfBasicType.new# ADSL::DS::TypeSig::BasicType::STRING
              :unknown
            end
          end

          roles.each do |role, role_class|
            current_user_code = <<-RUBY.strip
              #{role_class}.new(:adsl_ast => ADSL::Lang::ASTCurrentUser.new)
            RUBY

            controller_class.class_eval <<-ruby
              def authenticate_#{role}!(*args); @current_#{role} = current_#{role}; end
              def #{role}_signed_in?(*args); true; end
              def current_#{role}(*args); #{ current_user_code }; end
              def #{role}_session(*args); ::ADSL::Extract::MetaUnknown.new; end
              def only_render_implemented_actions(*args); end
              def respond_with(*args); ::ADSL::Lang::ASTFlag.new(:label => :render); end
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

        def instrument_gem_paper_trail(controller_class, action)
          return unless Object.lookup_const('PaperTrail')
        end

        def prepare_paper_trail_models
          return unless Object.lookup_const('PaperTrail')

          version_class = Object.lookup_or_create_class 'PaperTrail::Version', ActiveRecord::Base
          version_class.class_exec do
            belongs_to :item, :polymorphic => true
          end
          # generator = ActiveRecordMetaclassGenerator.new version_class
          # @ar_classes << generator.generate_class

          ActiveRecord::Base.class_exec do
            include PaperTrail

            def self.has_paper_trail
              has_many :versions, :class_name => 'PaperTrail::Version', :as => :item
            end
          end
        end

        def instrument_gem_active_admin(controller_class, action)
          return unless Object.lookup_const('ActiveAdmin')

          collection_name = controller_class.controller_name
          instance_name = collection_name.singularize
          class_name = controller_class.controller_name.singularize.camelize
          method_pattern = <<-ruby
            def ${1}(*args)
              ins_explore_all :${1} do
                ADSL::Lang::ASTAssignment.new(
                  :var_name => ADSL::Lang::ASTIdent["at__${2}"],
                  :expr => ${3}.adsl_ast
                )
              end
            end
          ruby
          case action
          when :index
            controller_class.class_eval method_pattern.resolve_params(:index, collection_name, "#{class_name}.where")
          when :show
            controller_class.class_eval method_pattern.resolve_params(:show, instance_name, "#{class_name}.find")
          # when :new
          #   controller_class.class_eval method_pattern.resolve_params(:create, instance_name, "#{class_name}.new")
          when :create
            controller_class.class_eval method_pattern.resolve_params(:create, instance_name, "#{class_name}.new")
          when :edit
            controller_class.class_eval method_pattern.resolve_params(:edit, instance_name, "#{class_name}.find")
          when :update
            controller_class.class_eval method_pattern.resolve_params(:update, instance_name, "#{class_name}.find")
          when :destroy
            controller_class.class_eval <<-ruby, __FILE__, __LINE__
              def destroy
                ins_explore_all :destroy do
                  ins_block(ADSL::Lang::ASTAssignment.new(
                    :var_name => ADSL::Lang::ASTIdent["at__#{collection_name}"],
                    :expr => #{class_name}.where.adsl_ast
                  ),
                  ADSL::Lang::ASTDeleteObj.new(
                    :objset => ADSL::Lang::ASTVariableRead.new(
                      :var_name => ADSL::Lang::ASTIdent["at__#{collection_name}"]
                    )
                  ))
                end
              end
            ruby
          end
        end

        def instrument_gem_has_scope(controller_class, action)
          return unless Object.lookup_const('HasScope')

          controller_class.class_exec do
            def apply_scopes(klass)
              klass.where
            end
          end
        end

        def instrument_gems(controller_class, action)
          instrument_gem_ransack controller_class, action
          instrument_gem_authlogic controller_class, action
          instrument_gem_devise controller_class, action
          instrument_gem_paperclip controller_class, action
          instrument_gem_paper_trail controller_class, action
          instrument_gem_active_admin controller_class, action
          instrument_gem_has_scope controller_class, action
        end

      end
    end
  end
end
