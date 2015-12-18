if ENV['RACK_ENV'] == 'production'
  # Heroku
  # https://gist.github.com/Geesu/d0b58488cfae51f361c6
  namespace :assets do
    task 'precompile' do
      puts "Not applicable"
    end
  end
else
  require "bundler/gem_tasks"
  require 'rspec/core/rake_task'
  require 'attache/tasks'

  RSpec::Core::RakeTask.new(:spec)
  task :default => :spec
end
