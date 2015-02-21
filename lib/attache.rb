module Attache
  class << self
    attr_accessor :localdir, :remotedir, :storage, :logger, :bucket
  end
end

Attache.logger    = Logger.new(STDOUT)
Attache.localdir  = File.expand_path(ENV.fetch('LOCAL_DIR') { Dir.mktmpdir })
Attache.remotedir = ENV['REMOTE_DIR'] # nil means no fixed top level remote directory, and that's fine.

if ENV['FOG_CONFIG'] && (config = JSON.parse(ENV['FOG_CONFIG']))
  Attache.storage = Fog::Storage.new(config.symbolize_keys)
  Attache.bucket  = config['s3_bucket']
end
