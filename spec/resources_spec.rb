require 'spec_helper'

describe AlchemyFlux::Service do

  after(:each) do
    # This will stop EventMachine and disconnect RabbitMQ, reseting each test
    AlchemyFlux::Service.stop
  end

  describe "#send_request_to_resource" do

    it 'should be able to send messages to resource via path' do
      resource_path = "/v1/fluxy_#{AlchemyFlux::Service.generateUUID()}"
      service_a = AlchemyFlux::Service.new("fluxa.send_service", resource_paths: [resource_path], :timeout => 200) do |message|
        {'body' => "hi #{message['body']['name']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.send_service")

      service_a.start
      service_b.start

      sleep(1)

      response = service_b.send_request_to_resource({'path' => resource_path, 'body' => {'name' => "Bob"}})
      expect(response['body']).to eq "hi Bob"

      response = service_b.send_request_to_resource({'path' => "#{resource_path}/id", 'body' => {'name' => "Alice"}})
      expect(response['body']).to eq "hi Alice"

      service_a.stop
      service_b.stop
    end

    it 'should be able to register multiple resources' do
      resource_path1 = "/v1/fluxy_#{AlchemyFlux::Service.generateUUID()}"
      resource_path2 = "/v1/fluxy_#{AlchemyFlux::Service.generateUUID()}"
      service_a = AlchemyFlux::Service.new("fluxa.send_service1", resource_paths: [resource_path1, resource_path2], :timeout => 200) do |message|
        {'body' => "hi #{message['body']['name']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.send_service1")

      service_a.start
      service_b.start

      sleep(1)

      response = service_b.send_request_to_resource({'path' => resource_path1, 'body' => {'name' => "Bob"}})
      expect(response['body']).to eq "hi Bob"

      response = service_b.send_request_to_resource({'path' => resource_path2, 'body' => {'name' => "Alice"}})
      expect(response['body']).to eq "hi Alice"
      service_a.stop
      service_b.stop
    end


    describe 'unhappy path' do
      it 'should return error on a message to non existant service' do
        service_b = AlchemyFlux::Service.new("fluxb.send_service3", :timeout => 200)

        service_b.start

        expect(service_b.send_request_to_resource({'path' => '/v1/unregistered_resource'})).to eq AlchemyFlux::MessageNotDeliveredError
        expect(service_b.transactions.length).to eq 0

        service_b.stop
      end

    end
  end

  describe "#send_message_to_resource" do
    it 'should be able to send messages to resource via path' do
      resource_path = "/v1/fluxy_#{AlchemyFlux::Service.generateUUID()}"
      recieved_count = 0
      service_a = AlchemyFlux::Service.new("fluxa.send_service", resource_paths: [resource_path]) do |message|
        recieved_count += 1
        {}
      end

      service_b = AlchemyFlux::Service.new("fluxb.send_service")

      service_a.start
      service_b.start

      sleep(1)
      expect(recieved_count).to be 0
      response = service_b.send_request_to_resource({'path' => resource_path, 'body' => {'name' => "Bob"}})
      sleep(0.1)
      expect(recieved_count).to be 1
      response = service_b.send_request_to_resource({'path' => "#{resource_path}/id", 'body' => {'name' => "Alice"}})
      sleep(0.1)
      expect(recieved_count).to be 2

      service_a.stop
      service_b.stop
    end

  end
end