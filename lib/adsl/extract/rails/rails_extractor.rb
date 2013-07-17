require 'adsl/extract/rails/active_record_extractor'
require 'adsl/extract/rails/action_instrumenter'
require 'adsl/extract/rails/invariant_extractor'
require 'adsl/extract/rails/other_meta'
require 'adsl/parser/ast_nodes'
require 'pathname'

module ADSL
  module Extract
    module Rails
      class RailsExtractor
        attr_accessor :class_map, :actions, :invariants

        def initialize(options = {})
          options = Hash[
            :ar_classes => default_activerecord_models,
            :invariants => Dir['invariants/**/*_invs.rb']
          ].merge options
          
          @active_record_instrumenter = ADSL::Extract::Rails::ActiveRecordExtractor.new
          @class_map = @active_record_instrumenter.extract_static options[:ar_classes]
          
          @action_instrumenter = ADSL::Extract::Rails::ActionInstrumenter.new(@class_map.keys.map{ |n| n.name.split('::').last })
          @actions = all_routes.map{ |route| action_to_adsl_ast route }
          
          @invariant_extractor = ADSL::Extract::Rails::InvariantExtractor.new
          @invariants = @invariant_extractor.extract(options[:invariants]).map{ |inv| inv.adsl_ast }
        end

        def all_routes
          ::Rails.application.routes.routes.map{ |route|
            {
              :request_method => request_method_for(route),
              :url => url_for(route),
              :controller => controller_of(route),
              :action => action_of(route)
            }
          }.select{ |route|
            !route[:action].nil? &&
            !route[:controller].nil? &&
            !route[:url].nil? &&
            !route[:request_method].nil?
          }.uniq{ |a| [a[:controller], a[:action]] }
        end

        def route_for(controller, action)
          all_routes.select{ |a| a[:controller] == controller && a[:action] == action.to_sym}.first
        end

        def action_to_adsl_ast(route)
          @action_instrumenter.action_block = []
          @action_instrumenter.instrument route[:controller].new, route[:action]

          session = ActionDispatch::Integration::Session.new(::Rails.application)
          
          @action_instrumenter.exec_within do
            session.send(route[:request_method].to_s.downcase, route[:url], ADSL::Extract::Rails::MetaUnknown.new)
          end

          ADSL::Parser::ASTAction.new({
            :name => ADSL::Parser::ASTIdent.new(:text => "#{route[:controller]}__#{route[:action]}"),
            :arg_cardinalities => [],
            :arg_names => [],
            :arg_types => [],
            :block => ADSL::Parser::ASTBlock.new(:statements => @action_instrumenter.action_block)
          })
        ensure
          @action_instrumenter.action_block = []
        end

        def default_activerecord_models
          models_dir = Rails.respond_to?(:root) ? Rails.root.join('app', 'models') : Pathname.new('app/models')
          Dir[models_dir.join '**', '*.rb'].map do |path|
            /^#{Regexp.escape models_dir.to_s}\/(.*)\.rb$/.match(path)[1].camelize.constantize
          end
        end

        def controller_of(route)
          return nil unless route.defaults.include? :controller
          "#{route.defaults[:controller].camelize}Controller".constantize
        end

        def action_of(route)
          return nil unless route.defaults.include? :action
          route.defaults[:action].to_sym
        end

        def request_method_for(route)
          method_s = route.verb.source.match(/^\^?(.*?)\$?$/)[1]
          return nil if method_s.empty?
          method_s.to_sym
        end

        def url_for(route)
          params = {}
          route.required_parts.each do |part|
            params[part] = 0
          end
          route.format(params)
        end

        def adsl_ast
          ADSL::Parser::ASTSpec.new(
            :classes => @class_map.map{ |klass, metaklass| metaklass.adsl_ast },
            :actions => @actions,
            :invariants => @invariants
          )
        end
      end
    end
  end
end
