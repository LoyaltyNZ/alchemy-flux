# Test Rack Service
require 'alchemy-flux'

ENV['SERVICE_NAME'] = 'test.service'
ENV['RESOURCE_PATHS'] = '/test/bob,/test/alice'

app = Proc.new do |env|
  ['200', {}, ["hi #{env['PATH_INFO']}"]]
end

run( app )
