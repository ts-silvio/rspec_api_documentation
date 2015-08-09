require 'rspec/core/formatters/base_formatter'
require 'rack/utils'
require 'rack/test/utils'

module RspecApiDocumentation::DSL
  # DSL methods available inside the RSpec example.
  module Endpoint
    extend ActiveSupport::Concern
    include Rack::Test::Utils

    delegate :response_headers, :response_status, :response_body, :to => :rspec_api_documentation_client

    module ClassMethods
      def example_request(description, params = {}, &block)
        example description, :caller => block.send(:caller) do
          do_request(params)
          instance_eval &block if block_given?
        end
      end

      private

      # from rspec-core
      def relative_path(line)
        line = line.sub(File.expand_path("."), ".")
        line = line.sub(/\A([^:]+:\d+)$/, '\\1')
        return nil if line == '-e:1'
        line
      end
    end

    def do_request(extra_params = {})
      @extra_params = extra_params

      params_or_body = nil
      path_or_query = path

      if http_method == :get && !query_string.blank?
        path_or_query += "?#{query_string}"
      else
        if respond_to?(:raw_post)
          params_or_body = raw_post
        else
          formatter = RspecApiDocumentation.configuration.post_body_formatter
          case formatter
          when :json
            params_or_body = params.empty? ? nil : params.to_json
          when :xml
            params_or_body = params.to_xml
          when Proc
            params_or_body = formatter.call(params)
          else
            params_or_body = params
          end
        end
      end

      rspec_api_documentation_client.send(http_method, path_or_query, params_or_body, headers)
    end

    def query_string
      build_nested_query(params || {})
    end

    def params
      parameters = example.metadata.fetch(:parameters, {}).inject({}) do |hash, param|
        set_param(hash, param)
      end
      parameters.deep_merge!(extra_params)
      parameters
    end

    def header(name, value)
      example.metadata[:headers] ||= {}
      example.metadata[:headers][name] = value
    end

    def headers
      return unless example.metadata[:headers]
      example.metadata[:headers].inject({}) do |hash, (header, value)|
        if value.is_a?(Symbol)
          hash[header] = send(value) if respond_to?(value)
        else
          hash[header] = value
        end
        hash
      end
    end

    def http_method
      example.metadata[:method]
    end

    def method
      http_method
    end

    def status
      rspec_api_documentation_client.status
    end

    def in_path?(param)
      path_params.include?(param)
    end

    def path_params
      example.metadata[:route].scan(/:(\w+)/).flatten
    end

    def path
      example.metadata[:route].gsub(/:(\w+)/) do |match|
        if extra_params.keys.include?($1)
          delete_extra_param($1)
        elsif respond_to?($1)
          send($1)
        else
          match
        end
      end
    end

    def explanation(text)
      example.metadata[:explanation] = text
    end

    def example
      RSpec.current_example
    end

    private

    def rspec_api_documentation_client
      send(RspecApiDocumentation.configuration.client_method)
    end

    def extra_params
      return {} if @extra_params.nil?
      @extra_params.inject({}) do |h, (k, v)|
        v = v.is_a?(Hash) ? v.stringify_keys : v
        h[k.to_s] = v
        h
      end
    end

    def delete_extra_param(key)
      @extra_params.delete(key.to_sym) || @extra_params.delete(key.to_s)
    end

    def set_param(hash, param)
      key = param[:name]
      return hash if !respond_to?(key) || in_path?(key)

      if scope = param[:scope]
        if scope.is_a?(Array)
          hash.merge!(scope.reverse.inject({key => send(key)}) { |a,n| { n.to_s => a }})
        else
          hash[scope.to_s] ||= {}
          hash[scope.to_s][key] = send(key)
        end
      else
        hash[key] = send(key)
      end

      hash
    end
  end
end
