require 'time'
require 'amqp'
require "uuidtools"
require 'msgpack'

require 'alchemy-flux/flux_rack_handler.rb'

# Alchemy Flux module
module AlchemyFlux

  # Error created when a Service message times out
  class TimeoutError < StandardError; end

  # Error created when a Message is unable to be delivered to a service
  class MessageNotDeliveredError < StandardError; end

  # Error used by a service when they wish the calling message to be NACKed *dangerous*
  class NAckError < StandardError; end

  # An Alchemy Flux Service
  class Service

    # The current state of the Service, either *stopped* or *started*
    attr_reader :state

    # The outgoing message transactions
    attr_reader :transactions

    # The incoming number of messages being processed
    attr_reader :processing_messages

    # Generate a UUID string
    def self.generateUUID
      UUIDTools::UUID.random_create.to_i.to_s(16).ljust(32,'0')
    end

    # Create a AlchemyFlux service instance
    #
    # +name+ the name of the service being created
    # +options+
    #
    def initialize(name, options = {}, &block)
      @name = name
      @options = {
          ampq_uri: 'amqp://localhost',
          prefetch: 20,
          timeout: 1000,
          threadpool_size: 500,
          resource_paths: []
      }.merge(options)

      @service_fn = block || Proc.new { |message| "" }

      @uuid = "#{@name}.#{AlchemyFlux::Service.generateUUID()}"
      @transactions = {}
      @processing_messages = 0

      @response_queue_name = @uuid
      @service_queue_name = @name
      @state = :stopped
    end

    # overriding inspect
    def inspect
      to_s
    end

    # overriding to_s
    def to_s
      "AlchemyFlux::Service(#{@name.inspect}, #{@options.inspect})"
    end

    # LIFE CYCLE


    # Start the EventMachine and AMQP connections for all Services
    #
    # The application has two or more threads
    # 1. The Controller Thread (e.g. the rspec thread)
    # 2. The EM Thread
    # 3. The EM defer Threads
    #
    # When we start a Service we do it in a Thread so that it will not block the calling Thread
    #
    # When the FIRST Service is started EM.run initialises in that Thread
    # When the second Service is initialises the block is executed in the new thread,
    # but all the callbacks will be executed in the EM thread
    #
    def self.start(ampq_uri = 'amqp://localhost', threadpool_size=500)
      return if EM.reactor_running?
      start_blocker = Queue.new
      Thread.new do
        Thread.current["name"] = "EM Thread" if EM.reactor_thread?
        Thread.current.abort_on_exception = true
        EM.threadpool_size = threadpool_size
        AMQP.start(ampq_uri) do |connection|
          @@connection = connection
          @@connection.on_error do |conn, connection_close|
            message = "Channel exception: [#{connection_close.reply_code}] #{connection_close.reply_text}"
            puts message
            raise message
          end
          start_blocker << :unblock
        end
      end
      start_blocker.pop
    end

    # Stop EventMachine and the
    def self.stop
      return if !EM.reactor_running?
      stop_blocker = Queue.new

      #last tick
      AMQP.stop do
        EM.stop_event_loop
        stop_blocker << :unblock
      end
      stop_blocker.pop
      sleep(0.05) # to ensure it finished
    end

    # start the service
    def start
      return if @state != :stopped

      Service.start(@options[:ampq_uri], @options[:threadpool_size])
      EM.run do

        @channel = AMQP::Channel.new(@@connection)

        @channel.on_error do |ch, channel_close|
          message = "Channel exception: [#{channel_close.reply_code}] #{channel_close.reply_text}"
          puts message
          raise message
        end

        @channel.prefetch(@options[:prefetch])
        @channel.auto_recovery = true

        @service_queue = @channel.queue( @service_queue_name, {:durable => true})
        @service_queue.subscribe({:ack => true}) do |metadata, payload|
          payload = MessagePack.unpack(payload)
          process_service_queue_message(metadata, payload)
        end

        response_queue = @channel.queue(@response_queue_name, {:exclusive => true, :auto_delete => true})
        response_queue.subscribe({}) do |metadata, payload|
          payload = MessagePack.unpack(payload)
          process_response_queue_message(metadata, payload)
        end

        @channel.default_exchange.on_return do |basic_return, frame, payload|
          payload = MessagePack.unpack(payload)
          process_returned_message(basic_return, frame.properties, payload)
        end

        # RESOURCES HANDLE
        @resources_exchange = @channel.topic("resources.exchange", {:durable => true})
        @resources_exchange.on_return do |basic_return, frame, payload|
          payload = MessagePack.unpack(payload)
          process_returned_message(basic_return, frame.properties, payload)
        end

        bound_resources = 0
        for resource_path in @options[:resource_paths]
          binding_key = "#{path_to_routing_key(resource_path)}.#"
          @service_queue.bind(@resources_exchange, :key => binding_key) {
            bound_resources += 1
          }
        end
        begin
          # simple loop to wait for the resources to be bound
          sleep(0.01)
        end until bound_resources == @options[:resource_paths].length

        @state = :started
      end
    end

    # Stop the Service
    #
    # This method:
    # * Stops receiving new messages
    # * waits for processing incoming and outgoing messages to be completed
    # * close the channel
    def stop
      return if @state != :started
      # stop receiving new incoming messages
      @service_queue.unsubscribe
      # only stop the service if all incoming and outgoing messages are complete
      decisecond_timeout = @options[:timeout]/100
      waited_deciseconds = 0 # guarantee that this loop will stop
      while (@transactions.length > 0 || @processing_messages > 0) && waited_deciseconds < decisecond_timeout
        sleep(0.1) # wait a decisecond to check the incoming and outgoing messages again
        waited_deciseconds += 1
      end

      @channel.close
      @state = :stopped
    end

    # END OF LIFE CYCLE



    private
    # RECIEVING MESSAGES

    # process messages on the service queue
    def process_service_queue_message(metadata, payload)

      service_to_reply_to = metadata.reply_to
      message_replying_to = metadata.message_id
      this_message_id = AlchemyFlux::Service.generateUUID()
      delivery_tag = metadata.delivery_tag

      operation = proc {
        @processing_messages += 1
        begin
          response = @service_fn.call(payload)
          {
            'status_code' => response['status_code'] || 200,
            'body' => response['body']               || ""
          }
        rescue AlchemyFlux::NAckError => e
          AlchemyFlux::NAckError
        rescue Exception => e
          puts "Service Fn Error " + e.inspect

          # Returning Hoodoo formatted Error code (just in case service doesnt handle the error, it should!)
          {
            'status_code' => 500,
            'headers' => {'Content-Type' => 'application/json; charset=utf-8'},
            'body' =>   {
              'kind' =>           "Errors",
              'id' =>             AlchemyFlux::Service.generateUUID(),
              'created_at' =>     Time.now.utc.iso8601,
              'errors' => [{'code' => 'platform.fault', 'message' => 'An unexpected error occurred'}]
            }
          }
        end
      }

      callback = proc { |result|

        if result == AlchemyFlux::NAckError
          @service_queue.reject(delivery_tag)
        else
          options = {
            :message_id     => this_message_id,
            :correlation_id => message_replying_to,
            :type           =>    'http_response'
          }
          send_message(@channel.default_exchange, service_to_reply_to, result, options)
          @processing_messages -= 1
          @service_queue.acknowledge(delivery_tag)
        end
      }

      EventMachine.defer(operation, callback)
    end

    # process a response message
    #
    # If a message is put on this services response queue
    # its response will be pushed onto the blocking queue
    def process_response_queue_message(metadata, payload)
      response_queue = @transactions.delete metadata.correlation_id
      response_queue << payload if response_queue
    end

    # process a returned message
    #
    # If a message is sent to a queue that cannot be found,
    # rabbitmq returns that message to this method
    def process_returned_message(basic_return, metadata, payload)
      response_queue = @transactions.delete metadata[:message_id]
      response_queue << MessageNotDeliveredError if response_queue
    end

    # END OF RECIEVING MESSAGES

    # SENDING MESSAGES

    private

    # send a message to an exchange with routing key
    #
    # *exchange*:: A AMQP exchange
    # *routing_key*:: The routing key to use
    # *message*:: The message to be sent
    # *options*:: The message options
    def send_message(exchange, routing_key, message, options)
      message_options = options.merge({:routing_key => routing_key})
      message = MessagePack.pack(message)
      EventMachine.next_tick do
        exchange.publish message, message_options
      end
    end

    public

    # send a message to the default exchange with routing key
    #
    # *routing_key*:: The routing key to use
    # *message*:: The message to be sent
    # *options*:: The message options
    def send_message_on_default_exchange(routing_key, message, options = {})
      send_message( @channel.default_exchange, routing_key, message, options )
    end

    # send a message to a service
    #
    # *service_name*:: the name of the service
    # *message*:: the message to be sent
    #
    # This method can optionally take a block which will be executed asynchronously and yielded the response
    def send_message_to_service(service_name, message)
      if block_given?
        EventMachine.defer do
          yield send_message_to_service(service_name, message)
        end
      else
        send_HTTP_request_message(@channel.default_exchange, service_name, message)
      end
    end

    # send a message to a resource
    #
    # *message*:: the message to be sent to the *path* in the message
    #
    # This method can optionally take a block which will be executed asynchronously and yielded the response
    def send_message_to_resource(message)
      routing_key = path_to_routing_key(message['path'])
      if block_given?
        EventMachine.defer do
          yield send_message_to_resource(message)
        end
      else
        send_HTTP_request_message(@resources_exchange, routing_key, message)
      end
    end


    private

    # Takes a path and converts it into a routing key
    #
    # *path*:: path string
    #
    # For example, path '/test/path' will convert to routing key 'test.path'
    def path_to_routing_key(path)
      new_path = ""
      path.split('').each_with_index do |c,i|
        if c == '/' and i != 0 and i != path.length-1
          new_path += '.'
        elsif c != '/'
          new_path += c
        end
      end
      new_path
    end

    # send a HTTP message to an exchange with routing key
    #
    # *exchange*:: A AMQP exchange
    # *routing_key*:: The routing key to use
    # *message*:: The message to be sent
    def send_HTTP_request_message(exchange, routing_key, message)

      http_message = {
        'session_id' =>  message['session_id'],
        'scheme' =>      message['protocol']    || 'http',
        'host' =>        message['hostname']    || 'localhost',
        'port' =>        message['port']        || 8080,
        'path' =>        message['path']        || "/",
        'query' =>       message['query']       || {},
        'verb' =>        message['verb']        || "GET",
        'headers' =>     message['headers']     || {},
        'body' =>        message['body']        || ""
      }

      message_id = AlchemyFlux::Service.generateUUID()

      http_message_options = {
        message_id:          message_id,
        type:               'http_request',
        reply_to:            @response_queue_name,
        content_encoding:    '8bit',
        content_type:        'application/octet-stream',
        expiration:           @options[:timeout],
        mandatory:            true
      }

      response_queue = Queue.new
      @transactions[message_id] = response_queue

      send_message(exchange, routing_key, http_message, http_message_options)

      EventMachine.add_timer(@options[:timeout]/1000.0) do
        response_queue = @transactions.delete message_id
        response_queue << TimeoutError if response_queue
      end

      response_queue.pop
    end

    # END OF SENDING MESSAGES

  end

end
