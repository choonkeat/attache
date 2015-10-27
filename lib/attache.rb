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

module Attache
  class << self
    attr_accessor :localdir,
                  :vhost,
                  :cache,
                  :logger,
                  :publicdir
  end
end

Attache.logger     = Logger.new(STDOUT)
Attache.localdir   = File.expand_path(ENV.fetch('LOCAL_DIR') { Dir.tmpdir })
Attache.vhost      = JSON.parse(ENV.fetch('VHOST') { YAML.load(IO.read('config/vhost.yml')).to_json rescue '{}' })
Attache.cache      = DiskStore.new(Attache.localdir, {
  cache_size: ENV.fetch('CACHE_SIZE_BYTES') {
    stat = Sys::Filesystem.stat("/")
    available = stat.block_size * stat.blocks_available
    (available * 0.8).floor # use 80% free disk by default
  }.to_i,
  reaper_interval:   ENV.fetch('CACHE_EVICTION_INTERVAL_SECONDS') { 60 }.to_i,
  eviction_strategy: (Attache.vhost.empty? ? nil : :LRU), # lru eviction only when there is remote storage
})
Attache.publicdir = ENV.fetch("PUBLIC_DIR") { File.expand_path("../public", File.dirname(__FILE__)) }

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
