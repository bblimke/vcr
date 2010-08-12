require 'webmock'
require 'vcr/extensions/net_http'

module VCR
  module HttpStubbingAdapters
    class WebMock < Base
      class << self
        VERSION_REQUIREMENT = '1.3.3'

        def check_version!
          unless meets_version_requirement?(::WebMock.version, VERSION_REQUIREMENT)
            raise "You are using WebMock #{::WebMock.version}.  VCR requires version #{VERSION_REQUIREMENT} or greater."
          end
        end

        def http_connections_allowed?
          ::WebMock::Config.instance.allow_net_connect
        end

        def http_connections_allowed=(value)
          ::WebMock::Config.instance.allow_net_connect = value
        end

        def stub_requests(http_interactions, match_attributes = RequestMatcher::DEFAULT_MATCH_ATTRIBUTES)
          requests = Hash.new([])

          http_interactions.each do |i|
            requests[i.request.matcher(match_attributes)] += [i.response]
          end

          requests.each do |request_matcher, responses|
            stub = ::WebMock.stub_request(request_matcher.method || :any, request_matcher.uri)

            with_hash = {}
            with_hash[:body]    = request_matcher.body    if request_matcher.match_requests_on?(:body)
            with_hash[:headers] = request_matcher.headers if request_matcher.match_requests_on?(:headers)

            stub = stub.with(with_hash) if with_hash.size > 0

            stub.to_return(responses.map{ |r| response_hash(r) })
          end
        end

        def create_stubs_checkpoint(checkpoint_name)
          checkpoints[checkpoint_name] = ::WebMock::RequestRegistry.instance.request_stubs.dup
        end

        def restore_stubs_checkpoint(checkpoint_name)
          ::WebMock::RequestRegistry.instance.request_stubs = checkpoints.delete(checkpoint_name)
        end

        def request_stubbed?(method, uri)
          !!::WebMock.registered_request?(::WebMock::RequestSignature.new(method, uri.to_s))
        end

        def request_uri(net_http, request)
          ::WebMock::NetHTTPUtility.request_signature_from_request(net_http, request).uri.to_s
        end

        def ignore_localhost=(value)
          ::WebMock::Config.instance.allow_localhost = value
        end

        def ignore_localhost?
          ::WebMock::Config.instance.allow_localhost
        end

        private

        def response_hash(response)
          {
            :body    => response.body,
            :status  => [response.status.code.to_i, response.status.message],
            :headers => response.headers
          }
        end

        def checkpoints
          @checkpoints ||= {}
        end
      end
    end
  end
end

WebMock.after_request(:except => [:net_http], :real_requests_only => true) do |request, response|
  http_interaction = VCR::HTTPInteraction.new(
    VCR::Request.new(
      request.method,
      request.uri.to_s,
      request.body,
      request.headers
    ),
    VCR::Response.new(
      VCR::ResponseStatus.new(
        response.status.first,
        response.status.last
      ),
      response.headers,
      response.body,
      '1.1'
    )
  )

  VCR.record_http_interaction(http_interaction)
end

if defined?(WebMock::NetConnectNotAllowedError)
  module WebMock
    class NetConnectNotAllowedError
      def message
        super + ".  You can use VCR to automatically record this request and replay it later.  For more details, see the VCR README at: http://github.com/myronmarston/vcr/tree/v#{VCR.version}"
      end
    end
  end
end
