require 'adsl/extract/rails/action_instrumenter'
require 'adsl/extract/rails/invariant_extractor'
require 'adsl/extract/rails/cancan_extractor'
require 'adsl/extract/rails/callback_chain_simulator'
require 'adsl/extract/rails/rails_special_gem_instrumentation'
require 'adsl/extract/rails/basic_type_extensions'
require 'adsl/extract/rails/other_meta'
require 'adsl/lang/ast_nodes'
require 'adsl/util/general'
require 'pathname'

module ADSL
  module Extract
    module Rails
      class RailsExtractor
        
        include ADSL::Extract::Rails::CallbackChainSimulator
        include ADSL::Extract::Rails::RailsSpecialGemInstrumentation
        include ADSL::Extract::Rails::CanCanExtractor
        
        attr_accessor :ar_classes, :actions, :invariants, :rules, :instrumentation_filters

        def cyclic_destroy_dependency?(options)
          classes = options[:ar_classes]
          destroy_deps = {}
          classes.each do |ar_class|
            dependent_assocs = ar_class.reflections.values.select{ |reflection|
              [:destroy, :destroy_all].include?(reflection.options[:dependent]) && reflection.options[:as].nil?
            }
            destroy_dep_class_names = dependent_assocs.map{ |refl| refl.through_reflection || refl }.map(&:class_name)
            destroy_deps[ar_class] = Set[*destroy_dep_class_names.select{ |a| Object.lookup_const a }.compact]
          end
          destroy_reachability = until_no_change Hash.new(Set.new) do |so_far|
            new_hash = so_far.dup
            classes.each do |ar_class|
              new_hash[ar_class] = destroy_deps[ar_class] + so_far[ar_class] + Set.new(so_far[ar_class].map{ |origin| destroy_deps[origin] }.flatten(1))
            end
            new_hash
          end
          classes.each do |origin|
            if destroy_reachability[origin].include?(origin)
              return true
            end
          end
          false
        end

        def initialize(options = {})
          @options = options = Hash[
            :ar_classes => default_activerecord_models,
            :invariants => Dir['invariants/**/*_invs.rb'],
            :instrumentation_filters => [],
            :actions => [],
            :include_empty_loops => false
          ].merge options
          
          raise "Cyclic destroy dependency detected. Translation aborted" if cyclic_destroy_dependency?(options)

          if options.include? :include_empty_loops
            ::ADSL::Lang::ASTForEach.include_empty_loops = options[:include_empty_loops]
          end

          @ar_classes = []

          prepare_paper_trail_models

          options[:ar_classes].each do |ar_class|
            generator = ActiveRecordMetaclassGenerator.new ar_class
            @ar_classes << generator.generate_class
          end
         
          @ar_classes.sort!{ |a, b| a.name <=> b.name }
          
          ar_class_names = @ar_classes.map(&:adsl_ast_class_name)
          
          @invariant_extractor = ADSL::Extract::Rails::InvariantExtractor.new ar_class_names
          @invariants = @invariant_extractor.extract(options[:invariants]).map(&:adsl_ast)
          @instrumentation_filters = @invariant_extractor.instrumentation_filters
          @instrumentation_filters += options[:instrumentation_filters]

          @action_instrumenter = ADSL::Extract::Rails::ActionInstrumenter.new ar_class_names
          @action_instrumenter.instrumentation_filters = @instrumentation_filters
          @actions = []

          @rules = Set[]

          prepare_cancan_instrumentation
          extract_ac_rules
        end
        
        def extract_all_actions
          routes = all_routes(@options[:actions])
          routes.each do |route|
            translation = action_to_adsl_ast(route)
            @actions << translation unless translation.nil?
          end
        end

        def all_routes(action_name_patterns = [])
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
          }.select{ |route|
            # ignore devise actions
            next false if route[:controller].to_s.downcase.start_with? 'devise'
            # ignore Rails 4 default controllers
            next false if route[:controller].to_s.downcase.start_with? 'rails'
            true
          }.select{ |route|
            next true if action_name_patterns.empty?
            action_name_patterns.map{ |patt| "#{ route[:controller] }__#{ route[:action] }".include? patt }.include? true
          }.sort{ |a, b| [a[:controller].to_s, a[:action]] <=> [b[:controller].to_s, b[:action]] }
        end

        def route_for(controller, action)
          all_routes.select{ |a| a[:controller] == controller && a[:action] == action.to_sym}.first
        end

        def action_name_for(route)
          "#{ route[:controller].name.gsub '::', '_' }__#{route[:action]}"
        end

        def callbacks(controller)
          controller.respond_to?(:_process_action_callbacks) ? controller._process_action_callbacks : []
        end

        def prepare_instrumentation(controller_class, action)
          controller_class.class_exec do
            def params
              ::ADSL::Extract::Rails::PartiallyUnknownParams.new controller_name, action_name
            end
            def default_render(*args); end
            def verify_authenticity_token; end
          end
          extractor_id = self.object_id
          controller_class.class_eval <<-ruby, __FILE__, __LINE__ + 1
            def rails_extractor
              ObjectSpace._id2ref #{ extractor_id }
            end
          ruby

          instrument_gems controller_class, action
          
          controller = controller_class.new
          @action_instrumenter.instrument controller, action
          callbacks(controller_class).each do |callback|
            next unless callback.filter.is_a?(Symbol)
            @action_instrumenter.instrument controller, callback.filter 
          end
        end

        def action_to_adsl_ast(route)
          instrumentation_allows = @instrumentation_filters.map do |f|
            f.allow_instrumentation? route[:controller].new, route[:action]
          end
          return nil if instrumentation_allows.include? false

          action_name = action_name_for route
          potential_adsl_asts = @actions.select{ |action| action.name.text == action_name }
          raise "Multiple actions with identical names" if potential_adsl_asts.length > 1
          return potential_adsl_asts.first if potential_adsl_asts.length == 1

          prepare_instrumentation route[:controller], route[:action]

          session = ActionDispatch::Integration::Session.new(::Rails.application)
          ::Rails.application.config.action_dispatch.show_exceptions = false

          root_method = ::ADSL::Extract::Rails::RootMethod.new
          @action_instrumenter.exec_within do
            instrumenter = ADSL::Extract::Instrumenter.get_instance

            instrumenter.ex_method = root_method
            instrumenter.action_name = route[:action].to_s

            request_method = route[:request_method].to_s.downcase.split('|').first
            
            session.send request_method, route[:url]

            instrumenter.ex_method = nil
          end
          session.reset!

          #interrupt_callback_chain_on_render block, route[:action]
          action = ADSL::Lang::ASTAction.new({
            :name => ADSL::Lang::ASTIdent[action_name],
            :expr => root_method.root_block
          })

          action.flatten_returns!

          action.remove_overwritten_assignments! route[:action]

          action.optimize!
          
          action.declare_instance_vars!
          
          action
        end

        def default_activerecord_models
          models_dir = Rails.respond_to?(:root) ? Rails.root.join('app', 'models') : Pathname.new('app/models')
          classes = Dir[models_dir.join '**', '*.rb'].map{ |path|
            klass = nil

            relative_path = /^#{Regexp.escape models_dir.to_s}\/(.*)\.rb$/.match(path)[1]
            parts = relative_path.split("/")
            klass_names = parts.each_index.map{ |index| parts.last(index+1).join('/').camelize }
            klass_names.each do |klass_name|
              next unless klass.nil?
              begin
                klass = klass_name.constantize
              rescue NameError, LoadError
              end
            end
            raise "Could not find class corresponding to path #{path}" if klass.nil?
            klass
          }.select{ |klass| klass < ActiveRecord::Base }
          classes = until_no_change(classes) do |classes|
            all = classes.dup
            classes.each do |c|
              all << c.superclass unless classes.include?(c.superclass) || c.superclass == ActiveRecord::Base
            end
            all
          end.uniq
          classes
        end

        def controller_of(route)
          return nil unless route.defaults.include? :controller
          controller_parts = route.defaults[:controller].split('/')
          controller_names = controller_parts.length.times.map{ |i| controller_parts.last(i+1).join '/' }
          
          possible_names = controller_names.map{ |cn| "#{cn}_controller" } + controller_names.map do |cn|
            other = cn == cn.singularize ? cn.pluralize : cn.singularize
            "#{ other }_controller"
          end
          possible_names.map! &:camelize
          possible_names.each do |name|
            begin
              return name.constantize
            rescue NameError
            end
          end
          raise "No controller class found for #{route.defaults}; attempted class names are #{possible_names}"
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
          klass_nodes = @ar_classes.map &:adsl_ast
          usergroups = []
          if authorization_defined?
            login_class = self.login_class
            klass_nodes.select{ |c| c.name.text == login_class.name }.each do |auth_node|
              auth_node.authenticable = true
            end
            usergroups = self.usergroups
          end
          spec = ADSL::Lang::ASTSpec.new(
            :classes => klass_nodes,
            :actions => @actions,
            :invariants => @invariants,
            :usergroups => usergroups,
            :rules => @rules,
            :ac_rules => generate_permits
          ).optimize!
        end
      end
    end
  end
end
