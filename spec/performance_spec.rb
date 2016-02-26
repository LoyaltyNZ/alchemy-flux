require 'spec_helper'

describe "performance of AlchemyFlux" do

  after(:each) do
    # This will stop EventMachine and disconnect RabbitMQ, reseting each test
    AlchemyFlux::Service.stop
  end

  it 'should handle multiple messages at the same time' do
    service_a = AlchemyFlux::Service.new("fluxa.service", {threadpool_size: 500}) do |message|
      {'body' => "hola #{message['body']['name']}"}
    end

    service_b = AlchemyFlux::Service.new("fluxb.service")

    service_a.start
    service_b.start

    calls = 400

    responses = Queue.new
    st = Time.now()
    (1..calls).each do
      service_b.send_request_to_service("fluxa.service", {'body' => {'name' => "Bob"}}) do |response|
        responses << response
      end
    end

    (1..calls).each do
      resp = responses.pop
      expect(resp['body']).to eq "hola Bob"
    end
    et = Time.now()
    puts "Time for #{calls} async calls is #{(et-st)*1000}ms total; #{((et-st)*1000)/calls}ms per call"
    service_a.stop
    service_b.stop
  end

  it 'should handle multiple messages at the same time' do
    service_a = AlchemyFlux::Service.new("fluxa.service", {threadpool_size: 500}) do |message|
      {'body' => "hola #{message['body']['name']}"}
    end

    service_b = AlchemyFlux::Service.new("fluxb.service")

    service_a.start
    service_b.start

    calls = 400

    st = Time.now()
    (1..calls).each do
      resp = service_b.send_request_to_service("fluxa.service", {'body' => {'name' => "Bob"}})
      expect(resp['body']).to eq "hola Bob"
    end

    et = Time.now()
    puts "Time for #{calls} sync calls is #{(et-st)*1000}ms total; #{((et-st)*1000)/calls}ms per call"
    service_a.stop
    service_b.stop
  end

end