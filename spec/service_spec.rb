require 'spec_helper'

describe AlchemyFlux::Service do
  def thread_count
    Thread.list.count
  end

  after(:each) do
    # This will stop EventMachine and disconnect RabbitMQ, reseting each test
    AlchemyFlux::Service.stop
  end

  describe '#initialize' do
    it 'be initializable' do
      AlchemyFlux::Service.new("test.service")
    end
  end

  describe '#Service.start' do
    it 'should create the EM thread' do
      init_thread_count = thread_count
      AlchemyFlux::Service.start
      expect(thread_count).to eq init_thread_count + 1
      AlchemyFlux::Service.stop
      expect(thread_count).to eq init_thread_count
    end

    it 'should raise an error if amqp uri is broken' do
      expect{AlchemyFlux::Service.start('bad_uri')}.to raise_error(ArgumentError)
      expect{AlchemyFlux::Service.start('amqp://localhosty')}.to raise_error(EventMachine::ConnectionError)
    end

    it 'should start the Service connection on instance start' do
      init_thread_count = thread_count
      service = AlchemyFlux::Service.new("testflux.service")
      service.start
      expect(thread_count).to eq init_thread_count + 1
      AlchemyFlux::Service.stop
      expect(thread_count).to eq init_thread_count
    end

    it 'should raise an error if amqp uri is broken on instance start' do
      service_bad_uri = AlchemyFlux::Service.new("testflux.service", ampq_uri: 'bad_uri')
      service_bad_server = AlchemyFlux::Service.new("testflux.service", ampq_uri: 'amqp://localhosty')
      expect{service_bad_uri.start}.to raise_error(ArgumentError)
      expect{service_bad_server.start}.to raise_error(EventMachine::ConnectionError)
    end
  end

  describe '#start' do

    it 'should start a service and increase thread count by 1' do
      init_thread_count = thread_count
      service = AlchemyFlux::Service.new("testflux.service")
      expect(service.state).to eq :stopped
      service.start
      expect(thread_count).to eq init_thread_count + 1
      expect(service.state).to eq :started
      #stop should not decrease because EM might still be running
      service.stop
      expect(service.state).to eq :stopped
      expect(thread_count).to eq init_thread_count + 1
    end

    it 'start and stop multiple services with no extra threads' do
      init_thread_count = thread_count

      service_a = AlchemyFlux::Service.new("testfluxa.service")
      service_b = AlchemyFlux::Service.new("testfluxb.service")

      service_a.start
      service_b.start

      expect(thread_count).to eq init_thread_count + 1

      service_a.stop
      service_b.stop

      expect(thread_count).to eq init_thread_count + 1
    end

    it 'should stop receiving messages after it has stopped' do
      received_message = false
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        received_message = true
        {}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service", timeout: 100)

      service_a.start
      service_b.start

      service_a.stop
      expect(service_b.send_message_to_service("fluxa.service", {})).to eq AlchemyFlux::TimeoutError
      service_b.stop
    end

    it 'should process incoming messages then stop' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        sleep(0.05)
        {'body' => "hello"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service", timeout: 200)

      service_a.start
      service_b.start

      response_queue = Queue.new
      service_b.send_message_to_service("fluxa.service", {}) do |response|
        response_queue << response
      end
      sleep(0.05)
      service_a.stop

      response = response_queue.pop

      expect(response['body']).to eq "hello"
      service_b.stop
    end

    it 'should process outgoing messages then stop' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        sleep(0.05)
        {'body' => "hello"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service", timeout: 200)

      service_a.start
      service_b.start

      response_queue = Queue.new
      service_b.send_message_to_service("fluxa.service", {}) do |response|
        response_queue << response
      end
      sleep(0.01)
      service_b.stop

      response = response_queue.pop

      expect(response['body']).to eq "hello"
      service_b.stop
    end

    it 'should stop receiving messages while stopping' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        sleep(0.8);
        {'body' => "hello"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start

      response_queue = Queue.new
      service_b.send_message_to_service("fluxa.service", {}) do |response|
        response_queue << response
      end
      sleep(0.1)
      Thread.new do service_a.stop end
      sleep(0.3)
      expect(service_b.send_message_to_service("fluxa.service", {})).to eq AlchemyFlux::TimeoutError

      response = response_queue.pop

      expect(response['body']).to eq "hello"
      service_b.stop
    end

    it 'should have default service function' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        {'body' => "hi #{message['body']['name']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start

      response = service_b.send_message_to_service("fluxa.service", {'body' => {'name' => "Bob"}})
      expect(response['body']).to eq "hi Bob"

      response = service_a.send_message_to_service("fluxb.service", {'body' => {'name' => "Bob"}})
      expect(response['body']).to be_empty


      service_a.stop
      service_b.stop
    end
  end

  describe "#send_message_on_default_exchange" do
    it 'should send a message to services' do
      received = false
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        received = true
        {}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start

      response = service_b.send_message_on_default_exchange("fluxa.service", {})
      sleep(0.1)
      expect(received).to be true
      service_a.stop
      service_b.stop
    end

  end

  describe "#send_message_to_service" do

    it 'should send and receive messages between services' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        {'body' => "hi #{message['body']['name']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start

      response = service_b.send_message_to_service("fluxa.service", {'body' => {'name' => "Bob"}})
      expect(response['body']).to eq "hi Bob"
      service_a.stop
      service_b.stop
    end


    it 'can send and receive messages JSON messages' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        body = JSON.parse(message['body'])
        {'body' => "hi #{body['name']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start

      response = service_b.send_message_to_service("fluxa.service", {'body' => '{"name" : "Bob"}'})
      expect(response['body']).to eq "hi Bob"
      service_a.stop
      service_b.stop
    end

    it 'should be able to send messages within the service call' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        resp = service_a.send_message_to_service("fluxb.service", {})
        {'body' => "hi #{resp['body']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service") do |message|
        {'body' => 'Bob'}
      end

      service_a.start
      service_b.start

      response = service_b.send_message_to_service("fluxa.service", {})
      expect(response['body']).to eq "hi Bob"
      service_a.stop
      service_b.stop
    end

    it 'should be able to send messages to itself' do
      first = true
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        if first
          first = !first
          resp = service_a.send_message_to_service("fluxa.service", {})
          {'body' => "hi #{resp['body']}"}
        else
          {'body' => 'Bob'}
        end
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start

      response = service_b.send_message_to_service("fluxa.service", {})
      expect(response['body']).to eq "hi Bob"
      service_a.stop
      service_b.stop
    end



    it 'should add to transactions and processing messages, and remove once complete' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        sleep(0.1)
        {'body' => 'here'}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service", timeout: 200)

      service_a.start
      service_b.start

      expect(service_b.transactions.length).to eq 0
      expect(service_a.processing_messages).to eq 0

      response = Queue.new
      service_b.send_message_to_service("fluxa.service", {}) do |resp|
        response << resp
      end
      sleep(0.05)
      expect(service_b.transactions.length).to eq 1
      expect(service_a.processing_messages).to eq 1

      expect(response.pop['body']).to eq 'here'
      expect(service_b.transactions.length).to eq 0
      expect(service_a.processing_messages).to eq 0

      service_a.stop
      service_b.stop
    end


    it 'should send and receive messages between services asynchronously' do
      service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
        {'body' => "hola #{message['body']['name']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start

      block = Queue.new
      service_b.send_message_to_service("fluxa.service", {'body' => {'name' => "Bob"}}) do |response|
        block << response
      end

      response = block.pop
      expect(response['body']).to eq "hola Bob"

      service_a.stop
      service_b.stop
    end

    describe 'unhappy path' do
      it 'should be able to be nacked by the service_fn' do
        called = 0
        service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
          called += 1
          raise AlchemyFlux::NAckError if called == 1
          { 'body' => "hola #{message['body']['name']}"}
        end

        service_b = AlchemyFlux::Service.new("fluxb.service")

        service_a.start
        service_b.start

        block = Queue.new
        service_b.send_message_to_service("fluxa.service", {'body' => {'name' => "Bob"}}) do |response|
          block << response
        end
        response = block.pop
        expect(response['body']).to eq "hola Bob"
        expect(called).to eq 2
        service_a.stop
        service_b.stop
      end

      it 'should timeout if a message takes too long' do
        service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
          sleep(0.1)
          {}
        end

        service_b = AlchemyFlux::Service.new("fluxb.service", timeout: 100)

        service_a.start
        service_b.start

        response = service_b.send_message_to_service("fluxa.service", {'body' => {'name' => "Bob"}})

        expect(response).to eq AlchemyFlux::TimeoutError
        expect(service_b.transactions.length).to eq 0

        service_a.stop
        service_b.stop
      end

      it 'should 500 if service_fn raises an error' do
        service_a = AlchemyFlux::Service.new("fluxa.service") do |message|
          raise Error.new
        end

        service_b = AlchemyFlux::Service.new("fluxb.service")

        service_a.start
        service_b.start

        response = service_b.send_message_to_service("fluxa.service", {'body' => {'name' => "Bob"}})

        expect(response['status_code']).to eq 500
        expect(service_b.transactions.length).to eq 0

        service_a.stop
        service_b.stop
      end

      it 'should return error on a message to non existant service' do
        service_b = AlchemyFlux::Service.new("fluxb.service")

        service_b.start

        expect(service_b.send_message_to_service("not_a_servoces.service", {})).to eq AlchemyFlux::MessageNotDeliveredError
        expect(service_b.transactions.length).to eq 0

        service_b.stop
      end

    end
  end
end