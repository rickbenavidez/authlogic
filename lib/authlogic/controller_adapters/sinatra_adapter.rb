# Authlogic bridge for Sinatra
module Authlogic
  module ControllerAdapters
    module SinatraAdapter
      # Cookie management functions
      class Cookies
        attr_reader :request, :response

        def initialize(request, response)
          @request = request
          @response = response
        end

        def delete(key, options = {})
          @response.delete_cookie(key, options)
        end

        def []=(key, options)
          @response.set_cookie(key, options)
        end

        def method_missing(meth, *args, &block)
          @request.cookies.send(meth, *args, &block)
        end
      end

      # Thin wrapper around request and response.
      class Controller
        attr_reader :request, :response, :cookies

        def initialize(request, response)
          @request = request
          @cookies = Cookies.new(request, response)
        end

        def session
          env["rack.session"]
        end

        def method_missing(meth, *args, &block)
          @request.send meth, *args, &block
        end
      end

      # Sinatra controller adapter
      class Adapter < AbstractAdapter
        def cookie_domain
          env["SERVER_NAME"]
        end

        # Mixed into `Sinatra::Base`
        module Implementation
          def self.included(klass)
            klass.send :before do
              controller = Controller.new(request, response)
              Authlogic::Session::Base.controller = Adapter.new(controller)
            end
          end
        end
      end
    end
  end
end

Sinatra::Base.send(:include, Authlogic::ControllerAdapters::SinatraAdapter::Adapter::Implementation)
