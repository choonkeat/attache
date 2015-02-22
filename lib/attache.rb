module Attache
  class << self
    attr_accessor :localdir,
                  :remotedir,
                  :storage,
                  :logger,
                  :bucket,
                  :geometry_alias,
                  :secret_key
  end
end

Attache.logger     = Logger.new(STDOUT)
Attache.localdir   = File.expand_path(ENV.fetch('LOCAL_DIR') { Dir.mktmpdir })
Attache.remotedir  = ENV['REMOTE_DIR'] # nil means no fixed top level remote directory, and that's fine.
Attache.secret_key = ENV['SECRET_KEY'] # nil means no auth check; anyone can upload a file

Attache.geometry_alias = JSON.parse(ENV.fetch('GEOMETRY_ALIAS') { '{}' })
# e.g. GEOMETRY_ALIAS='{ "small": "64x64#", "large": "128x128x#" }'

if ENV['FOG_CONFIG'] && (config = JSON.parse(ENV['FOG_CONFIG']))
  Attache.storage = Fog::Storage.new(config.symbolize_keys)
  Attache.bucket  = config['s3_bucket']
end
