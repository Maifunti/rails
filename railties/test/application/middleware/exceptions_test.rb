# frozen_string_literal: true

require "isolation/abstract_unit"
require "rack/test"

module ApplicationTests
  class MiddlewareExceptionsTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::Isolation
    include Rack::Test::Methods

    def setup
      build_app
    end

    def teardown
      teardown_app
    end

    test "show exceptions middleware filter backtrace before logging" do
      controller :foo, <<-RUBY
        class FooController < ActionController::Base
          def index
            raise 'oops'
          end
        end
      RUBY

      get "/foo"
      assert_equal 500, last_response.status

      log = File.read(Rails.application.config.paths["log"].first)
      assert_no_match(/action_dispatch/, log, log)
      assert_match(/oops/, log, log)
    end

    test "renders active record exceptions as 404" do
      controller :foo, <<-RUBY
        class FooController < ActionController::Base
          def index
            raise ActiveRecord::RecordNotFound
          end
        end
      RUBY

      get "/foo"
      assert_equal 404, last_response.status
    end

    test "renders unknown http methods as 405" do
      request "/", { "REQUEST_METHOD" => "NOT_AN_HTTP_METHOD" }
      assert_equal 405, last_response.status
    end

    test "uses custom exceptions app" do
      add_to_config <<-RUBY
        config.exceptions_app = lambda do |env|
          [404, { "Content-Type" => "text/plain" }, ["YOU FAILED"]]
        end
      RUBY

      app.config.action_dispatch.show_exceptions = true

      get "/foo"
      assert_equal 404, last_response.status
      assert_equal "YOU FAILED", last_response.body
    end

    test "URL generation error when action_dispatch.show_exceptions is set raises an exception" do
      controller :foo, <<-RUBY
        class FooController < ActionController::Base
          def index
            raise ActionController::UrlGenerationError
          end
        end
      RUBY

      app.config.action_dispatch.show_exceptions = true

      get "/foo"
      assert_equal 500, last_response.status
    end

    test "unspecified route when action_dispatch.show_exceptions is not set raises an exception" do
      app.config.action_dispatch.show_exceptions = false

      assert_raise(ActionController::RoutingError) do
        get "/foo"
      end
    end

    test "unspecified route when action_dispatch.show_exceptions is set shows 404" do
      app.config.action_dispatch.show_exceptions = true

      assert_nothing_raised do
        get "/foo"
        assert_match "The page you were looking for doesn't exist.", last_response.body
      end
    end

    test "unspecified route when action_dispatch.show_exceptions and consider_all_requests_local are set shows diagnostics" do
      app.config.action_dispatch.show_exceptions = true
      app.config.consider_all_requests_local = true

      assert_nothing_raised do
        get "/foo"
        assert_match "No route matches", last_response.body
      end
    end

    test "routing to a nonexistent controller when action_dispatch.show_exceptions and consider_all_requests_local are set shows diagnostics" do
      app_file "config/routes.rb", <<-RUBY
        Rails.application.routes.draw do
          resources :articles
        end
      RUBY

      app.config.action_dispatch.show_exceptions = true
      app.config.consider_all_requests_local = true

      get "/articles"
      assert_match "<title>Action Controller: Exception caught</title>", last_response.body
    end

    test "displays diagnostics message when exception raised in template that contains UTF-8" do
      controller :foo, <<-RUBY
        class FooController < ActionController::Base
          def index
          end
        end
      RUBY

      app.config.action_dispatch.show_exceptions = true
      app.config.consider_all_requests_local = true

      app_file "app/views/foo/index.html.erb", <<-ERB
        <% raise 'boooom' %>
        ✓測試テスト시험
      ERB

      get "/foo", utf8: "✓"
      assert_match(/boooom/, last_response.body)
      assert_match(/測試テスト시험/, last_response.body)
    end

    test "displays diagnostics message when malformed query parameters are provided" do
      controller :foo, <<-RUBY
        class FooController < ActionController::Base
          def index
          end
        end
      RUBY

      app.config.action_dispatch.show_exceptions = true
      app.config.consider_all_requests_local = true

      get "/foo?x[y]=1&x[y][][w]=2"
      assert_equal 400, last_response.status
      assert_match "Invalid query parameters", last_response.body
    end

    test "displays statement invalid template correctly" do
      controller :foo, <<-RUBY
        class FooController < ActionController::Base
          def index
            raise ActiveRecord::StatementInvalid
          end
        end
      RUBY
      app.config.action_dispatch.show_exceptions = true
      app.config.consider_all_requests_local = true
      app.config.action_dispatch.ignore_accept_header = false

      get "/foo"
      assert_equal 500, last_response.status
      assert_match "<title>Action Controller: Exception caught</title>", last_response.body
      assert_match "ActiveRecord::StatementInvalid", last_response.body

      get "/foo", {}, { "HTTP_ACCEPT" => "text/plain", "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest" }
      assert_equal 500, last_response.status
      assert_equal "text/plain", last_response.media_type
      assert_match "ActiveRecord::StatementInvalid", last_response.body
    end
  end
end
