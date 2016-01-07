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

        def permit(usergroups, action, objects)
          initialize_model_permissions
          usergroups = [usergroups || self.usergroups].flatten
          @entries << CancanPermissionEntry.new(usergroups, action, objects)
        end

        def generate_can_query_formula(action, subject)
          subject = classify_subject subject
          related_entries = @entries.select{ |e| e.related? action, subject }

          if subject.is_a?(Class) && subject < ActiveRecord::Base
            # just check whether the current user is of the right usergroup
            permitted_usergroups = Set[*related_entries.map(&:usergroups).flatten]
          
            ASTOr.new :subformulae => permitted_usergroups.map{ |ug|
              name = ASTIdent.new :text => ug.name.text
              ASTInUserGroup.new :groupname => name
            }
          elsif subject.respond_to? :adsl_ast
            groups_and_entries = Hash.new{ |hash, key| hash[key] = [] }
            related_entries.each do |entry|
              if entry.usergroups.empty?
                groups_and_entries[nil] << entry
              else
                entry.usergroups.each do |group|
                  groups_and_entries[group] << entry
                end
              end
            end
            ASTOr.new :subformulae => groups_and_entries.map{ |ug, entries|
              ug_condition = if ug.nil?
                ASTBoolean.new :bool_value => true
              else
                ASTInUserGroup.new :groupname => ASTIdent.new(:text => ug.name.text)
              end

              objsets = entries.map(&:objset).map &:adsl_ast
              ASTAnd.new :subformulae => [
                ug_condition,
                ASTIn.new(:objset1 => subject.adsl_ast, :objset2 => ASTUnion.new(:objsets => objsets))
              ]
            }
          else
            raise "Unknown subject for `#{ action }` permission check: #{ subject }"
          end
        end

        def generate_permits
          return [] if @entries.nil?
          entries = @entries.map(&:generate_permit).flatten.compact.uniq
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
          attr_reader :usergroups, :action, :subject

          def initialize(usergroups, action, subject)
            @usergroups = usergroups
            @action = action
            @subject = subject
          end

          def related?(action, subject)
            subject_class = subject.is_a?(Class) ? subject : subject.class
            ops_intersect = (inferred_ops & self.class.infer_ops(action))
            (subject_class <= @subject.class) && (ops_intersect.any? || @action.to_s == action.to_s)
          end

          def self.infer_ops(action)
            case action.to_sym
            when :manage
              [:create, :delete, :read]
            when :edit
              [:create, :delete]
            when :create, :new
              [:create]
            when :read, :index, :view, :show
              [:read]
            when :destroy
              [:delete]
            else
              []
            end
          end

          def inferred_ops
            self.class.infer_ops @action
          end

          def objset
            @subject.is_a?(Class) ? @subject.all : @subject
          end

          def to_s
            subject_objset = self.objset
            subject_text = subject_objset.respond_to?(:adsl_ast) ? subject_objset.adsl_ast.to_adsl : subject_objset
            ug_text = @usergroups.map(&:name).map(&:text).join ', '
            "#{ ug_text } can #{ @action } #{ subject_text }".strip
          end

          def generate_permit
            group_names = @usergroups.map{ |ug| ADSL::Parser::ASTIdent.new(:text => ug.name.text) }
            ops = inferred_ops
            ADSL::Parser::ASTPermit.new :group_names => group_names, :ops => ops, :expr => objset.adsl_ast if ops.any?
          end
        end

      end
    end
  end
end
