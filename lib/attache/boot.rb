require 'active_support/all'
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

require 'attache'
require 'attache/job'
require 'attache/resize_job'
require 'attache/base'
require 'attache/vhost'
require 'attache/upload'
require 'attache/delete'
require 'attache/download'
require 'attache/file_response_body'

require 'attache/tus'
require 'attache/tus/upload'
