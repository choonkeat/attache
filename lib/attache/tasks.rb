require "rake"

namespace :attache do

  desc "Convert content of FILE to a JSON string; default FILE=config/vhost.yml"
  task :vhost do
    require 'yaml'
    require 'json'

    file = ENV.fetch("FILE") { "config/vhost.yml" }
    puts YAML.load(IO.read(file)).to_json
  end

end
