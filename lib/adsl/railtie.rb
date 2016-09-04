require 'adsl'
require 'rails'
require 'adsl/extract/bin'

module ADSL
  class Railtie < Rails::Railtie

    def extract_arg(key)
      regex = /^#{key}\s*=\s*(.+)$/
      ARGV[1..-1].each do |arg|
        return arg.match(regex)[1] if regex =~ arg
      end
      nil
    end

    def extract_actions_param_from_args
      actions     = ("#{extract_arg('ACTION')    },#{extract_arg('ACTIONS')    }").split(',').map(&:strip).reject(&:empty?)
      controllers = ("#{extract_arg('CONTROLLER')},#{extract_arg('CONTROLLERS')}").split(',').map(&:strip).reject(&:empty?)
      if actions.empty? and controllers.empty?
        nil
      elsif actions.empty?
        controllers
      elsif controllers.empty?
        actions
      else
        action_controllers = []
        actions.each do |a|
          controllers.each do |c|
            action_controllers << "#{c}__#{a}"
          end
        end
        action_controllers
      end
    end

    include ADSL::Extract::Bin

    railtie_name :adsl

    rake_tasks do
      desc 'Verify Rails app logic'
      task :verify => :environment do
        verify_options = {}

        actions = extract_actions_param_from_args
        verify_options[:actions] = actions unless actions.nil?
        
        output = extract_arg('OUTPUT_FORMAT')
        unless output.nil? || output.strip.empty?
          verify_options[:output] = output.strip.downcase.to_sym
        end

        verify_spass :verify_options => verify_options
      end

      desc 'Translate Rails app into ADSL'
      task :adsl_translate => :environment do
        options = {}
        
        actions = extract_actions_param_from_args
        options[:actions] = actions unless actions.nil?
        options[:include_empty_loops] = extract_arg('INCLUDE_EMPTY_LOOPS') == 'true'

        adsl_translate :verify_options => options, :extract_options => options
      end
    end
  end
end
