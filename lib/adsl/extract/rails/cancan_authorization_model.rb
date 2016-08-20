require 'adsl/lang/ast_nodes'
require 'adsl/util/general'

module ADSL
  module Extract
    module Rails
      module CancanAuthorizationModel

        include ADSL::Lang

        def initialize_model_permissions
          @entries ||= Set[]
        end

        def permit(usergroups, action, objects, cannot=false)
          initialize_model_permissions
          usergroups = [usergroups || self.usergroups].flatten
          @entries << CancanPermissionEntry.new(usergroups, action, objects, cannot)
        end

        def generate_can_query_formula(action, subject)
          subject = classify_subject subject
          related_entries = @entries.select{ |e| e.related? action, subject }
          can_entries, cannot_entries = related_entries.select_reject &:can?
          
          if (subject.is_a?(Class) && subject < ActiveRecord::Base)
            # just check whether the current user is of the right usergroup
            permitted_usergroups = Set[*can_entries.map(&:usergroups).flatten]
            forbidden_usergroups = Set[*cannot_entries.map(&:usergroups).flatten]
            permitted_usergroups -= forbidden_usergroups
          
            ASTOr.new :subformulae => permitted_usergroups.map{ |ug|
              ASTInUserGroup.new :groupname => ASTIdent[ug.name.text]
            }
          elsif subject.respond_to? :adsl_ast
            groups_and_entries = Hash.new{ |hash, key| hash[key] = [] }
            usergroups_that_cannot = Set[*cannot_entries.map(&:usergroups).flatten]
            
            related_entries.each do |entry|
              if entry.usergroups.empty?
                groups_and_entries[nil] << entry
              else
                entry.usergroups.each do |group|
                  groups_and_entries[group] << entry unless usergroups_that_cannot.include? group
                end
              end
            end
            ASTOr.new :subformulae => groups_and_entries.map{ |ug, entries|
              ug_condition = if ug.nil?
                # any usergroup except the one that were marked to :cannot
                ASTNot.new(:subformula => ASTOr.new(
                  :subformulae => usergroups_that_cannot.map{ |ug|
                    ASTInUserGroup.new :groupname => ASTIdent.new(:text => ug.name.text)
                  }
                )).optimize
              else
                ASTInUserGroup.new :groupname => ASTIdent.new(:text => ug.name.text)
              end

              objsets = entries.map(&:objset).map &:adsl_ast
              ASTAnd.new :subformulae => [
                ug_condition,
                ASTIn.new(:objset1 => subject.adsl_ast, :objset2 => ASTUnion.new(:objsets => objsets))
              ]
            }
          elsif subject.is_a? Symbol
            # not supported
            ASTBoolean.new
          else
            raise "Unknown subject for `#{ action }` permission check: #{ subject }"
          end
        end

        def generate_permits
          return [] if @entries.nil?
          can_entries = Set[*@entries.select(&:can?).map(&:generate_permits).flatten]
          cannot_entries = Set[*@entries.select(&:cannot?).map(&:generate_permits).flatten]
          (can_entries - cannot_entries).to_a
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

          def initialize(usergroups, action, subject, cannot=false)
            @usergroups = usergroups
            @action = action
            @subject = subject
            @cannot = cannot
          end

          def cannot?
            @cannot
          end

          def can?
            !cannot?
          end

          def related?(action, subject)
            subject_class = subject.is_a?(Class) ? subject : subject.class
            ops_intersect = (inferred_ops & self.class.infer_ops(action))
            (subject_class <= @subject.class) && (ops_intersect.any? || @action.to_s == action.to_s || @action == :manage)
          end

          def self.infer_ops(action)
            case action.to_sym
            when :manage
              [:create, :delete, :read]
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

          def generate_permits
            group_nameses = @usergroups.map{ |ug| [ ADSL::Lang::ASTIdent[ug.name.text] ] }
            group_nameses << [] if group_nameses.empty?
            ops = inferred_ops
            group_nameses.map do |group_names|
              ops.map do |op|
                ADSL::Lang::ASTPermit.new :group_names => group_names, :ops => [op], :expr => objset.adsl_ast
              end
            end.flatten
          end
        end

      end
    end
  end
end
