$:.push File.expand_path( '../lib', __FILE__ )
require 'alchemy-flux/version'

Gem::Specification.new do |s|
  s.name        = 'alchemy-flux'
  s.version     = AlchemyFlux::VERSION
  s.date        = AlchemyFlux::DATE
  s.summary     = "Ruby implementation of the Alchemy micro-service framework"
  s.description = "Ruby implementation of the Alchemy micro-service framework"
  s.authors     = [ 'Loyalty New Zealand']
  s.email       = ['andrew.hodgkinson@loyalty.co.nz']
  s.license     = 'LGPL-3.0'

  s.files       = Dir.glob('lib/**/*.rb')
  s.test_files  = Dir.glob('spec/**/*.rb')

  s.required_ruby_version = '>= 2.2.7'
  s.add_development_dependency "rspec", '~> 3.4'
  s.add_development_dependency "rspec-mocks", '~> 3.4'
  s.add_development_dependency "rake", '~> 10.4'
  s.add_development_dependency "yard", '~> 0.8'
  s.add_runtime_dependency 'rack', '~> 2.0'
  s.add_runtime_dependency 'eventmachine', '~> 1.0'
  s.add_runtime_dependency 'amqp', '~> 1.5'
  s.add_runtime_dependency 'uuidtools', '~> 2.1'
end
