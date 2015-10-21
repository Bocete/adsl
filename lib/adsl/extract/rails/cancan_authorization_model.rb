require 'adsl/parser/ast_nodes'
require 'adsl/util/general'

module ADSL
  module Extract
    module Rails
      module CancanAuthorizationModel

        include ADSL::Parser

        def initialize_model_permissions
          @entries ||= Set[]
        end

        def permit(usergroup, op, objects)
          initialize_model_permissions
          @entries << CancanPermissionEntry.new(usergroup, op, objects)
        end

        def generate_can_query_formula(action, subject)
          subject = classify_subject subject
          related_entries = @entries.select{ |e| e.related? action, subject }

          if subject.is_a?(Class) && subject < ActiveRecord::Base
            # just check whether the current user is of the right usergroup
            permitted_usergroups = Set[*related_entries.map(&:usergroup)]
          
            ASTOr.new :subformulae => permitted_usergroups.map{ |ug|
              name = ASTIdent.new :text => ug.name.text
              ASTInUserGroup.new :groupname => name
            }
          elsif subject.is_a?(ActiveRecord::Base)
            groups_and_entries = related_entries.group_by &:usergroup
            ASTOr.new :subformulae => groups_and_entries.map{ |ug, entries|
              usergroup_name = ASTIdent.new :text => ug.name
              objsets = entries.map &:objset
              ASTAnd.new :subformulae => [
                ASTInUserGroup.new(:groupname => usergroup_name),
                ASTIn.new(:objset1 => subject.adsl_ast, :objset2 => ASTUnion.new(:objsets => objsets))
              ]
            }
          else
            raise "Unknown subject for `#{ action }` permission check: #{ subject }"
          end
        end

        def generate_permits
          return [] if @entries.nil? 
          @entries.map(&:generate_permit).flatten.compact
        end

        private

        def classify_subject(subject)
          if subject.is_a?(String) || subject.is_a?(Symbol)
            klass = Object.lookup_const subject
            return klass if klass
          end
          subject
        end

        class CancanPermissionEntry
          attr_reader :usergroup, :op, :subject

          def initialize(usergroup, op, subject)
            @usergroup = usergroup
            @op = op
            @subject = subject
          end

          def related?(action, subject)
            subject_class = subject.is_a?(Class) ? subject : subject.class
            subject_class <= @subject.class && (@op == :manage || @op == action)
          end

          def object_ops
            case @op.to_sym
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
          end

          def objset
            @subject.is_a?(Class) ? @subject.all : @subject
          end

          def generate_permit
            group_names = @usergroup ? [ADSL::Parser::ASTIdent.new(:text => @usergroup.name.text)] : []
            ops = object_ops

            ADSL::Parser::ASTPermit.new :group_names => group_names, :ops => ops, :expr => objset.adsl_ast if ops.any?
          end
        end

      end
    end
  end
end
