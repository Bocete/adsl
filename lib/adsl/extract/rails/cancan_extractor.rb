require 'adsl/parser/ast_nodes'
require 'adsl/extract/instrumenter'
require 'adsl/extract/rails/cancan_authorization_model'

module ADSL
  module Extract
    module Rails
      module CanCanExtractor

        include ADSL::Parser
        include ADSL::Extract::Rails::CancanAuthorizationModel

        def self.default_login_class
          consts = ['User', 'AdminUser']
          consts.each do |const|
            c = Object.lookup_const const
            return c if c
          end
          raise "Login class not found"
        end

        def login_class
          return @login_class if @login_class
          klass = CanCanExtractor.default_login_class
          raise "Login class #{ klass.name } is not a model class" unless klass < ActiveRecord::Base
          @login_class = klass
        end

        def define_login_class
          login_class
        end

        def define_usergroup(name)
          @usergroups ||= []
          return if @usergroups.any?{ |ug| ug.name.text == name.to_s }
          new_group = ADSL::Parser::ASTUserGroup.new(:name => ASTIdent.new(:text => name.to_s))
          @usergroups << new_group
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
            things_that_exist = Set[*(method_names + column_names)]
            if (things_that_exist & Set['admin', 'admin?', 'is_admin', 'is_admin?']).any?
              define_usergroup :admin
              define_usergroup :nonadmin
            end
          end
          
          @usergroups ||= []
          
          if @usergroups.count == 2
            @rules << ADSL::Parser::ASTRule.new(:formula => ADSL::Parser::ASTXor.new(
              :subformulae => @usergroups.map do |ug|
                ADSL::Parser::ASTInUserGroup.new(:groupname => ASTIdent.new(:text => ug.name.text))
              end
            ))
          end

          @usergroups
        end

        def define_usergroups
          usergroups
        end

        def define_usergroup_getters
          usergroups.map(&:name).map(&:text).each do |ug_name|
            login_class.class_eval <<-ruby
              def #{ug_name}
                ADSL::Parser::ASTInUserGroup.new(
                  :objset => ADSL::Parser::ASTCurrentUser.new,
                  :groupname => ADSL::Parser::ASTIdent.new(:text => '#{ug_name}')
                )
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
              rails_extractor.login_class.new :adsl_ast => ADSL::Parser::ASTCurrentUser.new
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
        
            def authorize!(*args)
              return if respond_to?(:should_authorize?) && (!should_authorize?)

              var_name = [instance_name, instance_name.pluralize].select{ |i| instance_variable_defined? "@#{i}" }.first

              if var_name
                subject = model_class.new(
                  :adsl_ast => ADSL::Parser::ASTVariable.new(
                    :var_name => ADSL::Parser::ASTIdent.new(:text => "at__#{var_name}")
                  )
                )
              else
                subject = controller_name.classify
              end

              auth_guarantee = rails_extractor.generate_can_query_formula action_name, subject
              
              ins_explore_all 'authorize' do
                ins_stmt ADSL::Parser::ASTAssertFormula.new(
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
          CanCan::ControllerResource.class_exec do
            def resource_instance=(instance)
              ins_explore_all 'load_resource_instance' do
                var_name = ADSL::Parser::ASTIdent.new(:text => "at__#{instance_name}")
                ins_stmt(ADSL::Parser::ASTAssignment.new(
                  :var_name => var_name,
                  :expr => instance.adsl_ast
                ))
              end
              @controller.instance_variable_set("@#{instance_name}", instance)
            end
            
            def collection_instance=(instance)
              ins_explore_all 'load_collection_instance' do
                ins_stmt(ADSL::Parser::ASTAssignment.new(
                  :var_name => ADSL::Parser::ASTIdent.new(:text => "at__#{instance_name.to_s.pluralize}"),
                  :expr => instance.adsl_ast
                ))
              end
              @controller.instance_variable_set("@#{instance_name.to_s.pluralize}", instance)
            end
          end
        end

        def instrument_ability
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
              ADSL::Parser::ASTNot.new :subformula => can?(*args)
            end

            def can(actions = nil, subject = nil, conditions_hash = nil, &block)
              return if ::ADSL::Extract::Instrumenter.get_instance.nil?
              return if ::ADSL::Extract::Instrumenter.get_instance.ex_method.nil?
              
              if subject == :all
                rails_extractor.ar_classes.each do |klass|
                  can actions, klass, conditions_hash, &block
                end
                return
              end
              actions = expand_actions [actions].flatten
              
              expr = nil
              login_class = CanCanExtractor.default_login_class
              equality_lhs = nil
              # try to deduce equality from arg hash
              if conditions_hash.present?
                conditions_hash.each do |key, val|
                  if val.is_a?(login_class) && val.adsl_ast.is_a?(ASTCurrentUser)
                    equality_lhs = subject.new(:adsl_ast => :subject).send(key)
                  end
                end
              end

              # try to deduce equality from block
              if block.present?
                raise 'we are not supporting blocks anymore. Too buggy'
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
                  reflection = subject.reflections[name]

                  inverse_refs = login_class.reflections.values.select do |r|
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
              
              ins_stmt(ADSL::Parser::ASTDummyStmt.new(:label => {
                :actions => actions,
                :domain => subject,
                :expr => expr,
              }))
            end
          end
        end

        def authorization_defined?
          cancan_exists?
        end
        
        def cancan_exists?
          Object.lookup_const('CanCan') && Object.lookup_const('Ability')
        end

        def freely_define_groups?
          Object.lookup_const 'Rolify'
        end

        def extract_rules_from_block(block, group = nil)
          block.statements.each do |stmt|
            if stmt.is_a?(ADSL::Parser::ASTBlock)
              extract_rules_from_block stmt
            elsif stmt.is_a?(ADSL::Parser::ASTIf)
              then_group, else_group = nil, nil
              if stmt.condition.is_a?(ADSL::Parser::ASTInUserGroup)
                is_group = stmt.condition
                then_group = @usergroups.select{ |g| stmt.condition.groupname.text.downcase == g.name.text.downcase }.first
                if then_group.nil?
                  if freely_define_groups?
                    define_usergroup stmt.condition.groupname.text
                  else
                    raise "Group by name #{stmt.condition.groupname.text} not found"
                  end
                end
                else_group = usergroups.select{ |g| g != then_group }.first if usergroups.length == 2
              end
              extract_rules_from_block stmt.then_block, then_group 
              extract_rules_from_block stmt.else_block, else_group
            elsif stmt.is_a?(ADSL::Parser::ASTDummyStmt) && stmt.label.is_a?(Hash)
              info = stmt.label

              actions = [info[:actions]].flatten
              next if actions.empty?
              
              if info[:domain] == :all
                klasses = @ar_classes
              else
                klasses = [info[:domain]].flatten
              end
              next if klasses.empty?

              groups = group ? [group] : @usergroups

              klasses.each do |klass|
                if info[:expr]
                  expr = info[:expr]
                else
                  if klass.is_a? Symbol
                    # klass may be unrelated to a class
                    klass = Object.lookup_const klass.to_s.classify
                    next if klass.nil?
                  end
                  expr = klass.all
                end

                actions.each do |action|
                  permit groups, action, expr
                end
              end
            end
          end
        end

        def extract_ac_rules
          return unless cancan_exists?

          current_user = login_class.new :adsl_ast => ADSL::Parser::ASTCurrentUser.new
          @action_instrumenter.instrument Ability.new(current_user), :initialize

          block = @action_instrumenter.exec_within do
            root_method = ADSL::Extract::Rails::Method.new :name => :root
            ADSL::Extract::Instrumenter.get_instance.ex_method = root_method
            ADSL::Extract::Instrumenter.get_instance.action_name = 'ability_block'
            statements = root_method.in_stmt_frame do
              Ability.new current_user
            end
            ADSL::Extract::Instrumenter.get_instance.ex_method = nil
            ADSL::Parser::ASTBlock.new :statements => statements
          end

          extract_rules_from_block(block)
        end

        def define_rolify_stuff
          return unless Object.lookup_const 'Rolify'

          Rolify::Role.class_exec do
            def has_role?(role_name, resource = nil)
              ADSL::Parser::ASTInUserGroup.new :groupname => ADSL::Parser::ASTIdent.new(:text => role_name.to_s)
            end
          end

          login_class.class_eval <<-add_role
            def add_role(role_name, resource = nil)
              rails_extractor = ObjectSpace._id2ref(#{ self.object_id })
              rails_extractor.define_usergroup role_name
            end
          add_role
        end

        def prepare_cancan_instrumentation
          return unless cancan_exists?

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
