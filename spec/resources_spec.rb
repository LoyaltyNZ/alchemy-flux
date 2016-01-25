require 'spec_helper'

describe AlchemyFlux::Service do

  after(:each) do
    # This will stop EventMachine and disconnect RabbitMQ, reseting each test
    AlchemyFlux::Service.stop
  end

  describe "#send_message_to_resource" do

    it 'should be able to send messages to resource via path' do
      resource_path = "/v1/fluxy_#{AlchemyFlux::Service.generateUUID()}"
      service_a = AlchemyFlux::Service.new("fluxa.service", resource_paths: [resource_path], :timeout => 200) do |message|
        {'body' => "hi #{message['body']['name']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start
      sleep(0.5)
      response = service_b.send_message_to_resource({'path' => resource_path, 'body' => {'name' => "Bob"}})
      expect(response['body']).to eq "hi Bob"

      response = service_b.send_message_to_resource({'path' => "#{resource_path}/id", 'body' => {'name' => "Alice"}})
      expect(response['body']).to eq "hi Alice"
      service_a.stop
      service_b.stop
    end

    it 'should be able to register multiple resources' do
      resource_path1 = "/v1/fluxy_#{AlchemyFlux::Service.generateUUID()}"
      resource_path2 = "/v1/fluxy_#{AlchemyFlux::Service.generateUUID()}"
      service_a = AlchemyFlux::Service.new("fluxa.service", resource_paths: [resource_path1, resource_path2], :timeout => 200) do |message|
        {'body' => "hi #{message['body']['name']}"}
      end

      service_b = AlchemyFlux::Service.new("fluxb.service")

      service_a.start
      service_b.start

      sleep(0.5)

      response = service_b.send_message_to_resource({'path' => resource_path1, 'body' => {'name' => "Bob"}})
      expect(response['body']).to eq "hi Bob"

      response = service_b.send_message_to_resource({'path' => resource_path2, 'body' => {'name' => "Alice"}})
      expect(response['body']).to eq "hi Alice"
      service_a.stop
      service_b.stop
    end


    describe 'unhappy path' do
      it 'should return error on a message to non existant service' do
        service_b = AlchemyFlux::Service.new("fluxb.service", :timeout => 200)

        service_b.start

        expect(service_b.send_message_to_resource({'path' => '/v1/unregistered_resource'})).to eq AlchemyFlux::MessageNotDeliveredError
        expect(service_b.transactions.length).to eq 0

        service_b.stop
      end

    end
  end
end