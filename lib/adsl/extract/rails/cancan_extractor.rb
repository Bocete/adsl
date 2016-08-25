require 'adsl/lang/ast_nodes'
require 'adsl/extract/instrumenter'
require 'adsl/extract/rails/cancan_authorization_model'

module ADSL
  module Extract
    module Rails
      module CanCanExtractor

        include ADSL::Lang
        include ADSL::Extract::Rails::CancanAuthorizationModel

        def default_login_class
          if devise_exists?
            candidates = ar_classes.select{ |c| c.included_modules.include? ::Devise::Models::DatabaseAuthenticatable }

            if candidates.length == 1
              return candidates.first
            end
          end
          consts = ['User', 'AdminUser']
          consts.each do |const|
            c = Object.lookup_const const
            return c if c
          end
          raise "Login class not found"
        end

        def login_class
          return @login_class if @login_class
          klass = default_login_class
          raise "Login class #{ klass.name } is not a model class" unless klass < ActiveRecord::Base
          @login_class = klass
        end

        def define_login_class
          klass = login_class
          CanCanExtractor.instance_variable_set :@login_class, klass
          klass
        end

        def self.login_class
          raise 'Login class undefined' unless instance_variable_defined? :@login_class
          @login_class
        end

        def define_usergroup(name)
          @usergroups ||= []
          matching_groups = @usergroups.select{ |ug| ug.name.text == name.to_s }
          return matching_groups.first if matching_groups.any?
          new_group = ASTUserGroup.new(:name => ASTIdent[name])
          @usergroups << new_group
          new_group
        end

        def usergroups
          return @usergroups if @usergroups && @usergroups.any?

          # see if roles are defined in the model
          roles = login_class.lookup_const 'ROLES'
          if roles
            roles.each do |role_name|
              define_usergroup role_name
            end
          else
            # see if 'admin' is defined somewhere, and if it is, define an admin usergroup
            method_names = login_class.instance_methods.map &:to_s
            column_names = login_class.column_names
            things_that_exist = Set[*(method_names + column_names).map(&:to_sym)]

            %w(admin administrator).each do |role|
              role_markers = [role, "#{role}?", "is_#{role}", "is_#{role}?"].map(&:to_sym)
              intersection = things_that_exist & Set[*role_markers]
              if intersection.any?
                define_usergroup role
                define_usergroup "non#{role}".to_sym
                break
              end
            end
          end
          
          @usergroups ||= []
          
          if @usergroups.count == 2
            @rules << ASTRule.new(:formula => ASTXor.new(
              :subformulae => @usergroups.map do |ug|
                ASTInUserGroup.new(:groupname => ASTIdent[ug.name.text])
              end
            ))
          end

          @usergroups
        end

        def define_usergroups
          usergroups
        end

        def define_usergroup_getters
          login_class.class_eval <<-ruby
            def rails_extractor
              ObjectSpace._id2ref #{ self.object_id }
            end
          ruby
          login_class.class_exec do
            def role?(sym)
              extractor = rails_extractor
              if extractor.freely_define_groups?
                extractor.define_usergroup sym
              end
              ADSL::Lang::ASTInUserGroup.new(
                :objset => self.adsl_ast,
                :groupname => ADSL::Lang::ASTIdent.new(:text => sym.to_s)
              )
            end
            alias_method :has_role?, :role?
          end
          usergroups.map(&:name).map(&:text).each do |ug_name|
            login_class.class_eval <<-ruby
              def #{ug_name}
                role? :#{ ug_name }
              end
              alias_method :#{ug_name}?, :#{ug_name}
              alias_method :is_#{ug_name}, :#{ug_name}
              alias_method :is_#{ug_name}?, :#{ug_name}
            ruby
          end
        end

        def define_controller_stuff
          ApplicationController.class_exec do
            def current_user
              rails_extractor.login_class.new :adsl_ast => ASTCurrentUser.new
            end

            def model_class_name
              self.class.controller_name.singularize.camelize
            end

            def model_class
              model_class_name.constantize
            end

            def name_from_controller
              self.class.controller_name.singularize
            end

            def namespace
              [ model_class_name.split('::')[0..-2].map{ |a| "'#{a}'" }.join(', ') ]
            end

            def instance_name
              controller_name.gsub('Controller', '').underscore.singularize
            end
        
            def authorize!(action = action_name, resource = nil, message = nil)
              @_authorized = true
              return if respond_to?(:should_authorize?) && (!should_authorize?)

              var_name = [instance_name, instance_name.pluralize].select{ |i| instance_variable_defined? "@#{i}" }.first

              if var_name
                subject = model_class.new(
                  :adsl_ast => ASTVariableRead.new(
                    :var_name => ASTIdent["at__#{var_name}"]
                  )
                )
              else
                subject = controller_name.classify
              end

              auth_guarantee = rails_extractor.generate_can_query_formula action, subject
              
              ins_explore_all 'authorize' do
                ASTAssertFormula.new(
                  :formula => auth_guarantee
                )
              end
            end

            def load_resource(*args)
              return if respond_to?(:should_load_resource?) && !should_load_resource?
              self.class.cancan_resource_class.new(self).load_resource
            end
          end
        end

        def define_controller_resource_stuff
          return unless cancan_exists?

          CanCan::ControllerResource.class_exec do
            def resource_instance=(instance)
              var_name = ASTIdent["at__#{instance_name}"]
              
              ins_explore_all 'load_resource_instance' do
                ASTAssignment.new(
                  :var_name => var_name,
                  :expr => instance.adsl_ast
                )
              end

              var_read = instance.class.new :adsl_ast => ASTVariableRead.new(:var_name => var_name.dup)
              @controller.instance_variable_set("@#{instance_name}", var_read)
            end
            
            def collection_instance=(instance)
              var_name = ASTIdent["at__#{instance_name.to_s.pluralize}"]
              
              ins_explore_all 'load_collection_instance' do
                ASTAssignment.new(
                  :var_name => var_name,
                  :expr => instance.adsl_ast
                )
              end

              var_read = instance.class.new :adsl_ast => ASTVariableRead.new(:var_name => var_name.dup)
              @controller.instance_variable_set("@#{instance_name.to_s.pluralize}", var_read)
            end
          end
        end

        def instrument_ability
          return unless cancan_exists?

          CanCan::Ability.class_eval <<-ruby
            def rails_extractor
              ObjectSpace._id2ref #{ self.object_id }
            end
          ruby
          CanCan::Ability.class_exec do
            def can?(action, subject, *args)
              rails_extractor.generate_can_query_formula action, subject
            end

            def cannot?(*args)
              ASTNot.new :subformula => can?(*args)
            end

            def process_ability_declaration(declaration, actions, subject, conditions_hash, &block)
              return if ::ADSL::Extract::Instrumenter.get_instance.nil?
              return if ::ADSL::Extract::Instrumenter.get_instance.ex_method.nil?

              if subject.is_a? Array
                return subject.map do |sub|
                  process_ability_declaration declaration, actions, sub, conditions_hash, &block
                end
              end
              
              if subject == :all
                return rails_extractor.ar_classes.map do |klass|
                  process_ability_declaration declaration, actions, klass, conditions_hash, &block
                end.flatten
              end
              actions = expand_actions [actions].flatten
              
              expr = nil
              equality_lhs = nil
              # try to deduce equality from arg hash
              if conditions_hash.present?
                conditions_hash.each do |key, val|
                  if val.try_adsl_ast.is_a?(ASTCurrentUser)
                    equality_lhs = subject.new(:adsl_ast => :subject).send(key)
                  end
                end
              end

              if block.present?
                # Blocks are too buggy for now
                # arg = subject.new :adsl_ast => :subject
                # result = block[arg]
                # if result.is_a?(ASTEqual)
                #   if result.exprs.any?{ |node| node.is_a? ASTCurrentUser }
                #     ignore_in_default = true
                #     equality_lhs = result.exprs.reject{ |node| node.is_a? ASTCurrentUser }.first
                #   end
                # end
              end

              if equality_lhs
                equality_lhs = equality_lhs.adsl_ast if equality_lhs.respond_to? :adsl_ast
                if equality_lhs == :subject
                  expr = subject.new :adsl_ast => ASTCurrentUser.new
                elsif equality_lhs.is_a?(ASTMemberAccess) && equality_lhs.objset == :subject
                  name = equality_lhs.member_name.text.to_sym
                  reflection = subject.reflections[name] || subject.reflections[name.to_s]

                  inverse_refs = CanCanExtractor.login_class.reflections.values.select do |r|
                    r.class_name == subject.name && r.foreign_key == reflection.foreign_key
                  end
                  if inverse_refs.length == 1
                    expr = subject.new :adsl_ast => ASTMemberAccess.new(
                      :objset => ASTCurrentUser.new,
                      :member_name => ASTIdent.new(:text => inverse_refs.first.name.to_s)
                    )
                  end
                end
              end
              
              ASTFlag.new(:label => {
                :declaration => declaration,
                :actions => actions,
                :domain => subject,
                :expr => expr,
              })
            end

            def cannot(actions = nil, subject = nil, conditions_hash = nil, &block)
              process_ability_declaration :cannot, actions, subject, conditions_hash, &block
            end

            def can(actions = nil, subject = nil, conditions_hash = nil, &block)
              process_ability_declaration :can, actions, subject, conditions_hash, &block
            end
          end
        end

        def authorization_defined?
          cancan_exists? || devise_exists? || Object.lookup_const('User')
        end
        
        def cancan_exists?
          Object.lookup_const('CanCan') && Object.lookup_const('Ability')
        end

        def freely_define_groups?
          Object.lookup_const 'Rolify'
        end

        def extract_rules_from_stmt(stmt, possible_groups)
          if stmt.is_a?(ASTBlock)
            stmt.exprs.each do |child|
              extract_rules_from_stmt child, possible_groups
            end
          elsif stmt.is_a?(ASTReturnGuard)
            extract_rules_from_stmt stmt.expr, possible_groups
          elsif stmt.is_a?(ASTIf)
            then_group, else_group = nil, nil
            if stmt.condition.is_a?(ASTInUserGroup)
              is_group = stmt.condition
              then_groups = possible_groups.select{ |g| stmt.condition.groupname.text.downcase == g.name.text.downcase }
              if then_groups.empty?
                if freely_define_groups?
                  then_groups = [define_usergroup(stmt.condition.groupname.text)]
                else
                  raise "Group by name #{stmt.condition.groupname.text} not found"
                end
              end
              else_groups = possible_groups - then_groups
            end
            then_groups = possible_groups if then_groups.nil?
            else_groups = possible_groups if else_groups.nil?
            extract_rules_from_stmt stmt.then_expr, then_groups
            extract_rules_from_stmt stmt.else_expr, else_groups
          elsif stmt.is_a?(ASTFlag) && stmt.label.is_a?(Hash)
            info = stmt.label

            actions = [info[:actions]].flatten
            return if actions.empty?
            
            if info[:domain] == :all
              klasses = @ar_classes
            else
              klasses = [info[:domain]].flatten
            end
            return if klasses.empty?

            declaration = info[:declaration]

            klasses.each do |klass|
              if info[:expr]
                expr = info[:expr]
              else
                if klass.is_a? Symbol
                  # klass may be unrelated to a class
                  klass = Object.lookup_const klass.to_s.classify
                  return if klass.nil?
                end
                expr = klass.all
              end

              actions.each do |action|
                permit possible_groups, action, expr, declaration == :cannot
              end
            end
          end
        end

        def extract_ac_rules
          return unless cancan_exists?

          current_user = login_class.new :adsl_ast => ASTCurrentUser.new
          @action_instrumenter.instrument Ability.new(current_user), :initialize

          root_method = ADSL::Extract::Rails::RootMethod.new
          @action_instrumenter.exec_within do
            ADSL::Extract::Instrumenter.get_instance.ex_method = root_method
            ADSL::Extract::Instrumenter.get_instance.action_name = 'ability_block'

            Ability.new current_user

            ADSL::Extract::Instrumenter.get_instance.ex_method = nil
          end
          block = root_method.root_block

          extract_rules_from_stmt block, usergroups
        end

        def define_rolify_stuff
          return unless Object.lookup_const 'Rolify'

          Rolify::Role.class_exec do
            def has_role?(role_name, resource = nil)
              role? role_name
              #ASTInUserGroup.new :groupname => ASTIdent[role_name.to_s]
            end
          end

          login_class.class_eval <<-add_role
            def add_role(role_name, resource = nil)
              rails_extractor = ObjectSpace._id2ref(#{ self.object_id })
              rails_extractor.define_usergroup role_name
              raise unless self.has_role? role_name
            end
          add_role
        end

        def prepare_cancan_instrumentation
          return unless authorization_defined?

          define_login_class
          define_usergroups
          define_usergroup_getters
          define_controller_stuff
          define_controller_resource_stuff
          define_rolify_stuff
          instrument_ability
        end

      end
    end
  end
end
