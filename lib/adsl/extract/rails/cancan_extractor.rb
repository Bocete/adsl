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

        def usergroups
          return @usergroups if @usergroups

          # see if roles are defined in the model
          roles = login_class.lookup_const 'ROLES'
          if roles
            @usergroups = roles.map{ |role_name| ASTUserGroup.new :name => ASTIdent.new(:text => role_name) }
          else
            # see if 'admin' is defined somewhere, and if it is, define an admin usergroup
            method_names = login_class.instance_methods.map &:to_s
            column_names = login_class.column_names
            things_that_exist = Set[*(method_names + column_names)]
            if (things_that_exist & Set['admin', 'admin?', 'is_admin', 'is_admin?']).any?
              admin    = ADSL::Parser::ASTUserGroup.new(:name => ASTIdent.new(:text => 'admin'))
              nonadmin = ADSL::Parser::ASTUserGroup.new(:name => ASTIdent.new(:text => 'nonadmin'))
              @usergroups = [nonadmin, admin]
            end
          end
          @usergroups ||= []
          
          if @usergroups.any?
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

            def can?(action, subject, *args)
              rails_extractor.generate_can_query_formula action, subject
            end

            def cannot?(*args)
              ADSL::Parser::ASTNot.new :subformula => can?(*args)
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
                subject = ADSL::Parser::ASTVariable.new(:var_name => ADSL::Parser::ASTIdent.new(:text => "at__#{var_name}"))
              else
                subject = controller_name.classify
              end

              condition = rails_extractor.generate_can_query_formula action_name, subject
              
              ins_stmt ADSL::Parser::ASTIf.new(
                :condition => condition,
                :then_block => ADSL::Parser::ASTBlock.new(:statements => []),
                :else_block => ADSL::Parser::ASTBlock.new(:statements => [
                  ADSL::Parser::ASTRaise.new
                ])
              )
            end
          end
        end

        def define_controller_resource_stuff
          CanCan::ControllerAdditions::ClassMethods.class_exec do
            def load_resource(*args)
              before_filter do
                ins_explore_all 'load_resource' do
                  old_load_resource

                  if load_instance?
                    if new_actions.include?(@params[:action].to_sym)
                      @controller.remove_instance_variable "@#{instance_name.to_s}"
                      return
                    else
                      var_name, value = instance_name.to_s, resource_base.find
                    end
                  else
                    var_name, value = instance_name.to_s.pluralize, resource_base.where
                  end

                  ins_stmt(ADSL::Parser::ASTAssignment.new(
                    :var_name => ADSL::Parser::ASTIdent.new(:text => "at__#{var_name}"),
                    :expr => value.adsl_ast
                  ))
                end
              end
            end
          end
        end

        def instrument_ability
          CanCan::Ability.class_exec do
            def can(actions = nil, subject = nil, conditions_hash = nil, &block)
              return if ::ADSL::Extract::Instrumenter.get_instance.nil?
              return if ::ADSL::Extract::Instrumenter.get_instance.ex_method.nil?
              
              expr = nil
              unless conditions_hash.nil?
                conditions_hash.each do |key, val|
                  login_class = CanCanExtractor.default_login_class
                  if val.is_a?(login_class) && val.adsl_ast.is_a?(ASTCurrentUser)
                    # either we're talking about the User class or some class that relates to User
                    if subject == login_class
                      expr = login_class.new(:adsl_ast => ASTCurrentUser.new)
                    else
                      # we need an inverse of that dereference
                      candidates = login_class.reflections.values.select do |refl|
                        refl.foreign_key.to_sym == key.to_sym && refl.class_name.constantize == subject
                      end
                      if candidates.length == 1
                        expr = login_class.new(:adsl_ast => ASTCurrentUser.new).send candidates.first.name
                      end
                    end
                  end
                end
              end
              
              ins_stmt(ADSL::Parser::ASTDummyStmt.new(:label => {
                :actions => actions,
                :domain => subject,
                :expr => expr
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

        def extract_rules_from_block(block, group = nil)
          block.statements.each do |stmt|
            if stmt.is_a?(ADSL::Parser::ASTBlock)
              extract_rules_from_block stmt
            elsif stmt.is_a?(ADSL::Parser::ASTIf)
              then_group, else_group = nil, nil
              if stmt.condition.is_a?(ADSL::Parser::ASTInUserGroup)
                is_group = stmt.condition
                then_group = @usergroups.select{ |g| stmt.condition.groupname.text.downcase == g.name.text.downcase }.first
                raise "Group by name #{stmt.condition.groupname.text} not found" if then_group.nil?
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
                  expr = klass.all
                end

                groups.each do |group|
                  actions.each do |action|
                    permit group, action, expr
                  end
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

        def prepare_cancan_instrumentation
          return unless cancan_exists?

          define_login_class
          define_usergroups
          define_usergroup_getters
          define_controller_stuff
          define_controller_resource_stuff
          instrument_ability
        end

      end
    end
  end
end
