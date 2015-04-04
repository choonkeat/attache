class Attache::VHost
  RETRY_DURATION = ENV.fetch('CACHE_EVICTION_INTERVAL_SECONDS') { 60 }.to_i / 3

  attr_accessor :remotedir,
                :secret_key,
                :file_options,
                :bucket,
                :storage,
                :geometry_alias,
                :download_headers,
                :headers_with_cors,
                :env

  def initialize(hash)
    self.env = hash || {}
    self.remotedir  = env['REMOTE_DIR'] # nil means no fixed top level remote directory, and that's fine.
    self.secret_key = env['SECRET_KEY'] # nil means no auth check; anyone can upload a file
    if env['FOG_CONFIG']
      self.file_options = env['FOG_CONFIG'].fetch('file_options')      { {} } # optional
      self.bucket       = env['FOG_CONFIG'].fetch('bucket')                   # required
      self.storage      = Fog::Storage.new(env['FOG_CONFIG'].except('bucket', 'file_options').symbolize_keys)
    else
      self.file_options = {}
    end
    self.geometry_alias = env.fetch('GEOMETRY_ALIAS') { {} }
    # e.g. GEOMETRY_ALIAS='{ "small": "64x64#", "large": "128x128x#" }'
    self.download_headers = env.fetch('DOWNLOAD_HEADERS') { {} }
    self.headers_with_cors = {
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Methods' => 'POST, PUT',
      'Access-Control-Allow-Headers' => 'Content-Type',
    }.merge(env['UPLOAD_HEADERS'] || {})
  end

  def hmac_for(content)
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), secret_key, content)
  end

  def hmac_valid?(params)
    params['uuid'] &&
    params['hmac']  &&
    params['expiration'] &&
    Time.at(params['expiration'].to_i) > Time.now &&
    Rack::Utils.secure_compare(params['hmac'], hmac_for("#{params['uuid']}#{params['expiration']}"))
  end

  def storage_get(relpath)
    url = storage.directories.new(key: bucket).files.new({
      key: File.join(*remotedir, relpath),
    }).url(Time.now + 60)
    open(url)
  end

  def storage_create(relpath)
    Attache.logger.info "[JOB] uploading #{relpath}"
    storage.directories.new(key: bucket).files.create({
      key: File.join(*remotedir, relpath),
      body: Attache.cache.read(relpath),
    })
    Attache.logger.info "[JOB] uploaded #{relpath}"
  end

  def storage_destroy(relpath)
    Attache.logger.info "[JOB] deleting #{relpath}"
    storage.directories.new(key: bucket).files.new({
      key: File.join(*remotedir, relpath),
    }).destroy
    Attache.logger.info "[JOB] deleted #{relpath}"
  end

  def async(method, relpath)
    Job.new.async.perform(method, env, relpath)
  end

  class Job
    include ::SuckerPunch::Job
    def perform(method, env, relpath)
      config = Attache::VHost.new(env)
      config.send(method, relpath)
    rescue Exception
      puts "[JOB] #{$!}", $@
      self.class.new.async.later(RETRY_DURATION, method, env, relpath)
    end
  end
end
