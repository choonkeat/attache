module Attache
  class << self
    attr_accessor :localdir,
                  :vhost,
                  :cache,
                  :logger
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
