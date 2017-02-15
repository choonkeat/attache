$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "attache/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "attache"
  s.version     = Attache::VERSION
  s.authors     = ["choonkeat"]
  s.email       = ["choonkeat@gmail.com"]
  s.homepage    = "https://github.com/choonkeat/attache"
  s.summary     = "Image server for everybody"
  s.description = "Standalone rack app to manage files onbehalf of your app"
  s.license     = "MIT"

  s.files       = Dir["{app,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md", 'exe/**/*',
                      "config/vhost.example.yml", "config/puma.rb", "config.ru", 'public/**/*']
  s.bindir      = 'exe'
  s.executables = ['attache']

  s.add_runtime_dependency 'rack', '~> 1.6'
  s.add_runtime_dependency 'activesupport'
  s.add_runtime_dependency 'paperclip', '~> 4.3'
  s.add_runtime_dependency 'puma', '~> 2.14'
  s.add_runtime_dependency 'net-ssh'
  s.add_runtime_dependency 'fog', '~> 1.34'
  s.add_runtime_dependency 'excon', '~> 0.45'
  s.add_runtime_dependency 'sys-filesystem', '~> 0'
  s.add_runtime_dependency 'disk_store', '~> 0'
  s.add_runtime_dependency 'celluloid', '< 0.17' # 0.17 has compatibility issues with disk_store
  s.add_runtime_dependency 'foreman', '~> 0'
  s.add_runtime_dependency 'connection_pool', '~> 2.2'
  s.add_runtime_dependency 'sidekiq', '~> 3.4'
  s.add_runtime_dependency 'sucker_punch', '~> 1.5' # single-process Ruby asynchronous processing library
  s.add_runtime_dependency 'mini_magick'

  s.add_development_dependency 'rspec', '~> 3.2'
  s.add_development_dependency 'shoulda', '~> 3.5'
  s.add_development_dependency 'guard-rspec', '~> 4.6'
end
