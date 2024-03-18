require 'rake'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new( :default ) do | t |
end

desc 'Generate documentation'
begin
  require 'yard'
  YARD::Rake::YardocTask.new do |t|
    t.files   = ['lib/**/*.rb', '-', 'docs/*.md']
    t.options = ['--main', 'README.md']
  end
rescue LoadError
  task :yard do puts "Please install yard first!"; end
end

desc 'Check if latest version in CHANGELOG.md matches with current version number'
task :check_version do
  changelog = File.join(File.dirname(__FILE__), 'CHANGELOG.md')
  raise "missing CHANGELOG.md" unless File.exist?(changelog)

  if File.read(changelog).match(/[0-9]+\.[0-9]+\.[0-9]+/)[0] != AlchemyFlux::VERSION
    raise "Latest version in CHANGELOG.md does not match AlchemyFlux::VERSION"
  end
end