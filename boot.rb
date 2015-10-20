require 'sys/filesystem'
require 'securerandom'
require 'disk_store'
require 'fileutils'
require 'paperclip'
require 'sidekiq'
require 'tmpdir'
require 'logger'
require 'base64'
require 'rack'
require 'json'
require 'uri'
require 'cgi'
require 'fog'

if ENV['REDIS_PROVIDER'] || ENV['REDIS_URL']
  # default sidekiq
elsif ENV['INLINE_UPLOAD']
  require 'sidekiq/testing/inline'
else
  require 'sucker_punch'
end

require './lib/attache.rb'
require './lib/attache/job.rb'
require './lib/attache/resize_job.rb'
require './lib/attache/base.rb'
require './lib/attache/vhost.rb'
require './lib/attache/upload.rb'
require './lib/attache/delete.rb'
require './lib/attache/download.rb'
require './lib/attache/file_response_body.rb'

require './lib/attache/tus.rb'
require './lib/attache/tus/upload.rb'
