module Attache
  class << self
    attr_accessor :localdir,
                  :remotedir,
                  :storage,
                  :cache,
                  :logger,
                  :bucket,
                  :geometry_alias,
                  :secret_key
  end
end

Attache.logger     = Logger.new(STDOUT)
Attache.localdir   = File.expand_path(ENV.fetch('LOCAL_DIR') { Dir.tmpdir })
Attache.remotedir  = ENV['REMOTE_DIR'] # nil means no fixed top level remote directory, and that's fine.
Attache.secret_key = ENV['SECRET_KEY'] # nil means no auth check; anyone can upload a file

Attache.geometry_alias = JSON.parse(ENV.fetch('GEOMETRY_ALIAS') { '{}' })
# e.g. GEOMETRY_ALIAS='{ "small": "64x64#", "large": "128x128x#" }'

if ENV['FOG_CONFIG'] && (config = JSON.parse(ENV['FOG_CONFIG']))
  Attache.storage = Fog::Storage.new(config.symbolize_keys)
  Attache.bucket  = config['s3_bucket']
end

if Attache.storage
  # lru eviction only when there is Attache.storage
  Attache.cache = DiskStore.new(Attache.localdir, {
    cache_size: ENV.fetch('CACHE_SIZE_BYTES') {
      stat = Sys::Filesystem.stat("/")
      available = stat.block_size * stat.blocks_available
      (available * 0.8).floor # use 80% free disk by default
    },
    reaper_interval:   ENV.fetch('CACHE_EVICTION_INTERVAL_SECONDS') { 60 },
    eviction_strategy: :LRU,
  })
else
  Attache.cache = DiskStore.new(Attache.localdir)
end

# summary
Attache.logger.info({
  storage: Attache.storage.class.name,
  secret_key: !!Attache.secret_key,
  cache: Attache.cache,
})
