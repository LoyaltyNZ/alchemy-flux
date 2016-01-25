require 'spec_helper'

describe Rack::Handler::AlchemyFlux do

  after(:each) do
    # This will stop EventMachine and disconnect RabbitMQ, reseting each test
    AlchemyFlux::Service.stop
  end

  describe "#start" do

    it 'should be able to start with a simple rack app' do
      ENV['ALCHEMY_SERVICE_NAME'] = 'rack.service'
      app = Proc.new do |env|
        ['200', {}, ['hi Bob']]
      end

      service_a = AlchemyFlux::Service.new("fluxa.service", :timeout => 200)
      Rack::Handler::AlchemyFlux.start app
      service_a.start
      sleep(0.5)
      response = service_a.send_message_to_service("rack.service", {})
      expect(response['body']).to eq "hi Bob"
      service_a.stop
      Rack::Handler::AlchemyFlux.stop
    end

    it 'should register resources with ALCHEMY_RESOURCE_PATHS env variable' do
      ENV['ALCHEMY_SERVICE_NAME'] = 'rack.service'
      ENV['ALCHEMY_RESOURCE_PATHS'] = '/alice,/bob'
      app = Proc.new do |env|
        ['200', {}, ["hi #{env['PATH_INFO']}"]]
      end

      service_a = AlchemyFlux::Service.new("fluxa.service", :timeout => 200)
      Rack::Handler::AlchemyFlux.start app

      service_a.start
      sleep(0.5)

      response = service_a.send_message_to_resource({'path' => '/alice'})
      expect(response['body']).to eq "hi /alice"

      response = service_a.send_message_to_resource({'path' => '/bob'})
      expect(response['body']).to eq "hi /bob"

      service_a.stop
      Rack::Handler::AlchemyFlux.stop
    end
  end
end