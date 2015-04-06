require 'adsl/parser/ast_nodes'
require 'adsl/extract/instrumenter'

module ADSL
  module Extract
    module Rails
      module CanCanExtractor
        include ADSL::Parser

        def self.auth_class
          consts = ['User', 'AdminUser']
          consts.each do |const|
            c = Object.lookup_const const
            return c unless c.nil?
          end
          raise "AuthClass not found"
        end

        def auth_class
          CanCanExtractor.auth_class
        end

        def ac_auth_class
          return @auth_class unless @auth_class.nil?
          klass = auth_class
          ac_klass = @ar_classes.select{ |c| c.name == klass.name }.first
          raise "ActiveRecord class for name '#{klass.name}' not found" if ac_klass.nil?
          @auth_class = ac_klass
          @auth_class
        end

        def define_auth_class
          auth_class
        end

        def usergroups
          return @usergroups unless @usergroups.nil?
          
          # see if roles are defined in the model
          roles = auth_class.lookup_const 'ROLES'
          if roles
            @usergroups = roles.map{ |role_name| ASTUserGroup.new :name => ASTIdent.new(:text => role_name) }
          else
            # see if 'admin' is defined somewhere, and if it is, define an admin usergroup
            method_names = auth_class.instance_methods.map &:to_s
            column_names = auth_class.column_names
            things_that_exist = Set[*(method_names + column_names)]
            unless (things_that_exist & Set['admin', 'admin?', 'is_admin', 'is_admin?']).empty?
              admin    = ADSL::Parser::ASTUserGroup.new(:name => ASTIdent.new(:text => 'admin'))
              nonadmin = ADSL::Parser::ASTUserGroup.new(:name => ASTIdent.new(:text => 'nonadmin'))
              @usergroups = [nonadmin, admin]
              @rules << ADSL::Parser::ASTRule.new(:formula => ADSL::Parser::ASTEqual.new(:exprs => [
                ADSL::Parser::ASTInUserGroup.new(:groupname => ASTIdent.new(:text => 'admin')),
                ADSL::Parser::ASTNot.new(:subformula => ASTInUserGroup.new(:groupname => ASTIdent.new(:text => 'nonadmin')))
              ]))
            end
          end

          @usergroups ||= []
          return @usergroups
        end

        def define_usergroups
          usergroups
        end

        def define_usergroup_getters
          usergroups.map(&:name).map(&:text).each do |ug_name|
            auth_class.class_eval <<-ruby
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
          ApplicationController.class_eval <<-ruby, __FILE__, __LINE__ + 1
            def current_user
              #{auth_class.name}.new(:adsl_ast => ADSL::Parser::ASTCurrentUser.new)
            end
          ruby
          ApplicationController.class_exec do
            def can?(action, subject, *args)
              ops = ADSL::Extract::Rails::CanCanExtractor.ops_from_action_name action
              if (subject.is_a? Class)
                ADSL::Parser::ASTPermittedByType.new(
                  :ops => ops,
                  :class_name => ADSL::Parser::ASTIdent.new(:text => subject.adsl_ast_class_name)
                )
              else
                ADSL::Parser::ASTPermitted.new(
                  :ops => ops,
                  :expr => subject.adsl_ast
                )
              end
            end

            def cannot?(*args)
              not can?(*args)
            end

            def model_class_name
              self.class.controller_name.singularize.camelize
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
          end

          CanCanExtractor.define_authorize!
        end

        def define_controller_resource_stuff
          CanCan::ControllerResource.class_exec do
            alias_method :old_load_resource, :load_resource
            def load_resource
              ins_explore_all 'load_resource' do
                old_load_resource

                var_name, value = if load_instance?
                  if new_actions.include?(@params[:action].to_sym)
                    [instance_name.to_s]
                  else
                    [instance_name.to_s, resource_base.find]
                  end
                else
                  [instance_name.to_s.pluralize, resource_base.where]
                end

                ins_stmt(ADSL::Parser::ASTAssignment.new(
                  :var_name => ADSL::Parser::ASTIdent.new(:text => "at__#{var_name}"),
                  :expr => value.adsl_ast
                ))
              end
            end

            #  unless skip?(:load)
            #    var_name, expr = if load_instance?
            #      if 
            #        # we won't create because actions tend to create another and
            #        # that is redundant in our translation
            #        [instance_name, nil]
            #      else
            #        [instance_name, resource_base.find]
            #      end
            #    else
            #      [instance_name.pluralize, resource_base.where]
            #    end

            #    ins_explore_all 'load_resource' do
            #      ins_stmt(ADSL::Parser::ASTAssignment.new(
            #        :var_name => ADSL::Parser::ASTIdent.new(:text => "at__#{var_name}"),
            #        :expr => expr.adsl_ast
            #      ))
            #      nil
            #    end

            #    value = resource_base.new(:adsl_ast => ADSL::Parser::ASTVariable.new(
            #      :var_name => ADSL::Parser::ASTIdent.new(:text => "at__#{var_name}")
            #    ))
            #    
            #    @controller.instance_variable_set("@#{ var_name }", value)
            #  end
            #end
          end
        end

        def self.define_authorize!
          ApplicationController.class_exec do
            def authorize!(*args)
              return if respond_to?(:should_authorize?) && (!should_authorize?)
              ops = ADSL::Extract::Rails::CanCanExtractor.ops_from_action_name action_name
              return if ops.empty?
              var_name = [instance_name, instance_name.pluralize].select{ |i| instance_variable_defined? "@#{i}" }.first
              if var_name.nil?
                ins_explore_all 'authorize_resource' do
                  ins_stmt(stmt = ADSL::Parser::ASTIf.new(
                    :condition => ADSL::Parser::ASTPermittedByType.new(
                      :ops => ops,
                      :class_name => ADSL::Parser::ASTIdent.new(:text => model_class_name)
                    ),
                    :then_block => ADSL::Parser::ASTBlock.new(:statements => []),
                    :else_block => ADSL::Parser::ASTBlock.new(:statements => [
                      ADSL::Parser::ASTRaise.new
                    ])
                  ))
                end
              else
                ins_explore_all 'authorize_resource' do
                  ins_stmt(stmt = ADSL::Parser::ASTIf.new(
                    :condition => ADSL::Parser::ASTPermitted.new(
                      :ops => ops,
                      :expr => ADSL::Parser::ASTVariable.new(:var_name => ADSL::Parser::ASTIdent.new(:text => "at__#{var_name}"))
                    ),
                    :then_block => ADSL::Parser::ASTBlock.new(:statements => []),
                    :else_block => ADSL::Parser::ASTBlock.new(:statements => [
                      ADSL::Parser::ASTRaise.new
                    ])
                  ))
                end
              end
            end
          end
        end

        def define_policy
          CanCan::Ability.class_exec do
            def can(action = nil, subject = nil, conditions_hash = nil, &block)
              return if ::ADSL::Extract::Instrumenter.get_instance.nil?
              return if ::ADSL::Extract::Instrumenter.get_instance.ex_method.nil?
              
              ops = ADSL::Extract::Rails::CanCanExtractor.ops_from_action_name action || :manage

              expr = nil
              unless conditions_hash.nil?
                conditions_hash.each do |key, val|
                  auth_class = CanCanExtractor.auth_class
                  if val.is_a?(auth_class) && val.adsl_ast.is_a?(ASTCurrentUser)
                    # either we're talking about the User class or some class that relates to User
                    if subject == auth_class
                      expr = ADSL::Parser::ASTCurrentUser.new
                    else
                      # we need an inverse of that dereference
                      candidates = auth_class.reflections.values.select do |refl|
                        refl.foreign_key.to_sym == key.to_sym && refl.class_name.constantize == subject
                      end
                      if candidates.length == 1
                        expr = ADSL::Parser::ASTMemberAccess.new(
                          :objset => ADSL::Parser::ASTCurrentUser.new,
                          :member_name => ADSL::Parser::ASTIdent.new(:text => candidates.first.name.to_s)
                        )
                      end
                    end
                  end
                end
              end
              
              ins_stmt(ADSL::Parser::ASTDummyStmt.new(:label => {
                :ops => ops,
                :domain => subject,
                :expr => expr
              }))
            end

            def authorize!(action, subject, *args)
              ops = ADSL::Extract::Rails::CanCanExtractor.ops_from_action_name action
              return if ops.empty?
              if subject.is_a?(ActiveRecord::Base)
                condition = ADSL::Parser::ASTPermitted.new(
                  :expr => subject.adsl_ast,
                  :ops => ops
                )
              else
                condition = ADSL::Parser::ASTPermittedByType.new(
                  :ops => ops,
                  :class_name => ADSL::Parser::ASTIdent.new(:text => subject.name)
                )
              end
              ins_stmt(ADSL::Parser::ASTIf.new(
                :condition => condition, 
                :then_block => ADSL::Parser::ASTBlock.new(:statements => []),
                :else_block => ADSL::Parser::ASTBlock.new(:statements => [
                  ADSL::Parser::ASTRaise.new
                ])
              ))
            end
          end
        end

        def self.ops_from_action_name(action)
          ops = case action.to_sym
          when :manage
            [:edit, :read]
          when :manage, :edit
            [:edit]
          when :create
            [:create]
          when :read, :index, :view, :show
            [:read]
          when :destroy
            [:delete]
          else
            []
          end
          ops.flatten.uniq
        end

        def authorization_defined?
          cancan_exists?
        end
        
        def cancan_exists?
          Object.lookup_const('CanCan') && Object.lookup_const('Ability')
        end

        def extract_rules_from_block(block, group = nil)
          block.statements.map do |stmt|
            if stmt.is_a?(ADSL::Parser::ASTBlock)
              extract_rules_from_block stmt
            elsif stmt.is_a?(ADSL::Parser::ASTIf) && stmt.condition.is_a?(ADSL::Parser::ASTInUserGroup)
              is_group = stmt.condition
              group = usergroups.select{ |g| stmt.condition.groupname.text.downcase == g.name.text.downcase }.first
              raise "Group by name #{stmt.condition.groupname.text} not found" if group.nil?
              othergroup = usergroups.select{ |g| g != group }.first if usergroups.length == 2
              [
                extract_rules_from_block(stmt.then_block, group), 
                extract_rules_from_block(stmt.else_block, othergroup)
              ]
            elsif stmt.is_a?(ADSL::Parser::ASTDummyStmt) && stmt.label.is_a?(Hash)
              info = stmt.label

              if info[:domain] == :all
                domains = @ar_classes.map(&:adsl_ast).map{ |c| [c] + ([c] * c.members.length).zip(c.members) }.flatten(1)
              else
                domains = [info[:domain].adsl_ast]
              end
              
              ops = info[:ops]

              domains.map do |domain|
                if info[:expr]
                  expr = info[:expr]
                elsif domain.is_a? ADSL::Parser::ASTClass
                  expr = ADSL::Parser::ASTAllOf.new(:class_name => ADSL::Parser::ASTIdent.new(:text => domain.name.text))
                else
                  expr = ADSL::Parser::ASTMemberAccess.new(
                    :objset => ADSL::Parser::ASTAllOf.new(:class_name => ADSL::Parser::ASTIdent.new(:text => domain[0].name.text)),
                    :member_name => ADSL::Parser::ASTIdent.new(:text => domain[1].name.text)
                  )
                end
                ADSL::Parser::ASTPermit.new(
                  :group_names => (group.nil? ? [] : [ADSL::Parser::ASTIdent.new(:text => group.name.text)]),
                  :ops => ops,
                  :expr => expr
                )
              end
            end
          end
        end

        def extract_ac_rules
          return unless cancan_exists?

          current_user = auth_class.new :adsl_ast => ADSL::Parser::ASTCurrentUser.new
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

          @ac_rules << extract_rules_from_block(block)
          @ac_rules.flatten!.compact!
        end

        def prepare_cancan_instrumentation
          return unless cancan_exists?

          define_auth_class
          define_usergroups
          define_usergroup_getters
          define_controller_stuff
          define_controller_resource_stuff
          define_policy
        end

      end
    end
  end
end
