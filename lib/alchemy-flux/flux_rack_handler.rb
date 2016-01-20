# This file creates a Service that Talks Rack
require 'rack'
require 'alchemy-flux'

# The Rack namespace
module Rack
  # The Rack Handlers namespace
  module Handler
    # Alchemy Rack handler
    class AlchemyFlux



      # Start the app server with the supplied Rack application and options
      #
      # +app+ [Rack Application] The Application to run.
      # +options+ [Hash] The options to start the server with.
      def self.run(app, options={})
        start(app)

        puts "Started #{@@service.inspect}"

        Signal.trap("INT")  do
          puts "Stopping #{@@service.inspect}"
          stop
        end

        Signal.trap("TERM") do
          puts "Stopping #{@@service.inspect}"
          stop
        end

        EM.reactor_thread.join
      end

      # start the service for rack
      def self.start(app)
        service_name = ENV['ALCHEMY_SERVICE_NAME']
        raise RuntimeError.new("Require ALCHEMY_SERVICE_NAME environment variable") if !service_name

        options = {
          ampq_uri: ENV['AMQ_URI'] || 'amqp://localhost',
          prefetch: ENV['PREFETCH'] || 20,
          timeout: ENV['TIMEOUT'] || 30000,
          threadpool_size: ENV['THREADPOOL_SIZE'] || 500,
          resource_paths: (ENV['ALCHEMY_RESOURCE_PATHS'] || '').split(',')
        }

        if options[:prefetch] > options[:threadpool_size]
          puts "WARNING: 'prefect' is greater than the available threads which may cause performance blocking problems"
        end

        @@service = ::AlchemyFlux::Service.new(service_name, options) do |message|
          rack_env = create_rack_env(message)

          # add Alchemy Service so the app may call other services
          rack_env['alchemy.service'] = @@service

          status, headers, body = app.call(rack_env)

          # process the body into a single response string
          body.close if body.respond_to?(:close)
          response = ""
          body.each { |part| response << part }

          {
            'status_code' => status,
            'headers' => headers,
            'body' => response
          }
        end


        @@service.start
      end

      # stops the app service
      def self.stop
        @@service.stop
        EM.stop
      end

      # create the environment hash to be sent to the app
      def self.create_rack_env(message)

        stream = StringIO.new(message['body'])
        stream.set_encoding(Encoding::ASCII_8BIT)


        # Full description of rack env http://www.rubydoc.info/github/rack/rack/master/file/SPEC
        rack_env = {}

        # CGI-like (adopted from PEP333) variables

        # The HTTP request method, such as “GET” or “POST”
        rack_env['REQUEST_METHOD'] = message['verb'].to_s.upcase

        # This is an empty string to correspond with the “root” of the server.
        rack_env['SCRIPT_NAME'] = ''

        # The remainder of the request URL's “path”, designating the virtual “location” of the request's target within the application.
        rack_env['PATH_INFO'] = message['path']

        # The portion of the request URL that follows the ?, if any
        rack_env['QUERY_STRING'] = Rack::Utils.build_query(message['query'])

        # Used to complete the URL
        rack_env['SERVER_NAME'] = message['host']
        rack_env['SERVER_PORT'] = message['port'].to_s


        # Headers are added to the rack env as described by RFC3875 https://www.ietf.org/rfc/rfc3875
        if message['headers'].is_a? Hash
          message['headers'].each do |name, value|
            name = "HTTP_" + name.to_s.upcase.gsub(/[^A-Z0-9]/,'_')
            rack_env[name] = value.to_s
          end
        end

        # The environment must not contain the keys HTTP_CONTENT_TYPE or HTTP_CONTENT_LENGTH (use the versions without HTTP_)
        rack_env['CONTENT_TYPE'] = rack_env['HTTP_CONTENT_TYPE'] || 'application/octet-stream'
        rack_env['CONTENT_LENGTH'] = rack_env['HTTP_CONTENT_LENGTH'] || stream.length.to_s
        rack_env.delete('HTTP_CONTENT_TYPE')
        rack_env.delete('HTTP_CONTENT_LENGTH')


        # Rack-specific variables

        # The Array representing this version of Rack See Rack::VERSION
        rack_env['rack.version'] = Rack::VERSION

        # http or https, depending on the request URL.
        rack_env['rack.url_scheme'] = message['scheme']

        # the input stream.
        rack_env['rack.input'] = stream

        # the error stream.
        rack_env['rack.errors'] = STDERR

        # true if the application object may be simultaneously invoked by another thread in the same process, false otherwise.
        rack_env['rack.multithread'] = true

        # true if an equivalent application object may be simultaneously invoked by another process, false otherwise.
        rack_env['rack.multiprocess'] = false

        # true if the server expects (but does not guarantee!) that the application will only be invoked this one time during the life of its containing process.
        rack_env['rack.run_once'] = false

        # present and true if the server supports connection hijacking.
        rack_env['rack.hijack?'] = false

        rack_env
      end
    end

    register :alchemy, Rack::Handler::AlchemyFlux
  end
end