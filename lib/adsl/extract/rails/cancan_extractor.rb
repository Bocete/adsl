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
          appController = Object.lookup_const 'ApplicationController'
          appController.class_eval <<-ruby
            def current_user; #{auth_class.name}.new(:adsl_ast => ADSL::Parser::ASTCurrentUser.new); end
            def extract_ops(action)
              ops = []
              [action].flatten.each do |op|
                case op
                when :manage
                  ops += [:edit, :read]
                when :edit
                  ops << :edit
                when :read, :create
                  ops << op
                when :destroy
                  ops << :delete
                end
              end
              ops
            end
            def can?(action, subject, *args)
              ops = extract_ops action
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
          ruby
        end

        def define_policy
          CanCan::Ability.class_exec do
            def can(action = nil, subject = nil, conditions_hash = nil, &block)
              return if ::ADSL::Extract::Instrumenter.get_instance.nil?
              return if ::ADSL::Extract::Instrumenter.get_instance.ex_method.nil?
              
              ops = []
              action ||= :manage
              if action == :manage || action == :update
                ops << [:edit, :read]
              elsif action == :create
                ops << [:create]
              elsif action == :read || action == :index || action == :view
                ops << [:read]
              elsif action == :destroy
                ops << [:delete]
              end
              ops.flatten!.uniq!

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
          end
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
          define_policy
        end

      end
    end
  end
end
