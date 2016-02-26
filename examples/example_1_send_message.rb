# # Example 1: Sending a message to a service
#
# Prerequisites:
# * RabbitMQ running

require 'alchemy-flux'

serviceA1 = AlchemyFlux::Service.new("A")

serviceB1 = AlchemyFlux::Service.new("B") do |message|
  {'body' => "Hello #{message['body']}"}
end

# Start the Services
serviceA1.start()
serviceB1.start()

# Service A1 sending message to B
response = serviceA1.send_request_to_service('B', {'body' => 'Alice'})

puts response['body'] # "Hello Alice"

serviceA1.stop()
serviceB1.stop()

