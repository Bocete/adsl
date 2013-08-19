require 'adsl/extract/rails/action_instrumenter'
require 'adsl/extract/rails/invariant_extractor'
require 'adsl/extract/rails/callback_chain_simulator'
require 'adsl/extract/rails/other_meta'
require 'adsl/parser/ast_nodes'
require 'pathname'

module ADSL
  module Extract
    module Rails
      class RailsExtractor
        
        include ADSL::Extract::Rails::CallbackChainSimulator
        
        attr_accessor :ar_classes, :actions, :invariants, :instrumentation_filters

        def initialize(options = {})
          options = Hash[
            :ar_classes => default_activerecord_models,
            :invariants => Dir['invariants/**/*_invs.rb'],
            :instrumentation_filters => []
          ].merge options
          
          @ar_classes = options[:ar_classes].map do |ar_class|
            generator = ActiveRecordMetaclassGenerator.new ar_class
            generator.generate_class
          end
          
          ar_class_names = @ar_classes.map(&:adsl_ast_class_name)
          
          @invariant_extractor = ADSL::Extract::Rails::InvariantExtractor.new ar_class_names
          @invariants = @invariant_extractor.extract(options[:invariants]).map{ |inv| inv.adsl_ast }
          @instrumentation_filters = @invariant_extractor.instrumentation_filters
          @instrumentation_filters += options[:instrumentation_filters]

          @action_instrumenter = ADSL::Extract::Rails::ActionInstrumenter.new ar_class_names
          @action_instrumenter.instrumentation_filters = @instrumentation_filters
          @actions = []
          all_routes.each do |route|
            @actions << action_to_adsl_ast(route)
          end
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
            !route[:request_method].nil? &&
            route[:controller].action_methods.include?(route[:action].to_s)
          }.uniq{ |a|
            [a[:controller], a[:action]]
          }.sort{ |a, b| [a[:controller].to_s, a[:action]] <=> [b[:controller].to_s, b[:action]] }
        end

        def route_for(controller, action)
          all_routes.select{ |a| a[:controller] == controller && a[:action] == action.to_sym}.first
        end

        def action_name_for(route)
          "#{route[:controller]}__#{route[:action]}"
        end

        def callbacks(controller)
          controller._process_action_callbacks
        end

        def prepare_instrumentation(controller_class, action)
          controller_class.class_exec do
            def default_render(*args); end
            def params; ADSL::Extract::Rails::MetaUnknown.new; end
          end
          controller = controller_class.new
          @action_instrumenter.instrument controller, action
          callbacks(controller_class).each do |callback|
            @action_instrumenter.instrument controller, callback.filter
          end
        end

        def action_to_adsl_ast(route)
          action_name = action_name_for route
          potential_adsl_asts = @actions.select{ |action| action.name.text == action_name }
          raise "Multiple actions with identical names" if potential_adsl_asts.length > 1
          return potential_adsl_asts.first if potential_adsl_asts.length == 1

          prepare_instrumentation route[:controller], route[:action]

          session = ActionDispatch::Integration::Session.new(::Rails.application)
          ::Rails.application.config.action_dispatch.show_exceptions = false

          block = @action_instrumenter.exec_within do
            @action_instrumenter.exec_within do
              session.send route[:request_method].to_s.downcase, route[:url]
            end
            @action_instrumenter.abb.root_lvl_adsl_ast 
          end

          interrupt_callback_chain_on_render block, route[:action]

          action = ADSL::Parser::ASTAction.new({
            :name => ADSL::Parser::ASTIdent.new(:text => action_name),
            :arg_cardinalities => [],
            :arg_names => [],
            :arg_types => [],
            :block => block
          })
          action = action.optimize
          action.prepend_global_variables_by_signatures /^at__.*/, /^atat__.*/
          action

          action
        end

        def default_activerecord_models
          models_dir = Rails.respond_to?(:root) ? Rails.root.join('app', 'models') : Pathname.new('app/models')
          Dir[models_dir.join '**', '*.rb'].map{ |path|
            /^#{Regexp.escape models_dir.to_s}\/(.*)\.rb$/.match(path)[1].camelize.constantize
          }.select{ |klass| klass < ActiveRecord::Base }
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
            :classes => @ar_classes.map(&:adsl_ast),
            :actions => @actions,
            :invariants => @invariants
          )
        end
      end
    end
  end
end
