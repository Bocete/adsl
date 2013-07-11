require 'adsl/extract/rails/rails_extractor'
require 'adsl/extract/rails/other_meta'
require 'adsl/parser/ast_nodes'

module ADSL
  module Extract
    module Rails
      class RailsExtractor

        def initialize(ar_classes = nil)
          @active_record_instrumenter = ADSL::Extract::Rails::ActiveRecordExtractor.new
         
          if ar_classes.nil?
            @class_map = @active_record_instrumenter.extract_static 'app/models'
          else
            @class_map = @active_record_instrumenter.extract_static_from_classes ar_classes
          end

          @action_instrumenter = ADSL::Extract::Rails::ActionInstrumenter.new(@class_map.keys.map{ |n| n.name.split('::').last })
        end

        def all_routes
          ::Rails.application.routes.routes.map{ |route|
            {
              :request_method => request_method_for(route),
              :url => url_for(route),
              :controller => controller_of(route),
              :action => action_of(route)
            }
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
            session.send route[:request_method].to_s.downcase, route[:url], ADSL::Extract::Rails::MetaUnknown.new
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

        def controller_of(route)
          "#{route.defaults[:controller].camelize}Controller".constantize
        end

        def action_of(route)
          route.defaults[:action].to_sym
        end

        def request_method_for(route)
          route.verb.to_s.match(/\^(.*)\$/)[1].to_sym
        end

        def url_for(route)
          params = {}
          route.required_parts.each do |part|
            params[part] = 0
          end
          route.format(params)
        end
      end
    end
  end
end
