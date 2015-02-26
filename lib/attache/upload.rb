class Attache::Upload < Attache::Base
  def initialize(app)
    @app = app
  end

  def call(env)
    case env['PATH_INFO']
    when '/upload'
      request  = Rack::Request.new(env)
      params   = request.params

      case env['REQUEST_METHOD']
      when 'POST', 'PUT', 'PATCH'
        if Attache.secret_key
          unless hmac_valid?(params)
            return [401, headers_with_cors.merge('X-Exception' => 'Authorization failed'), []]
          end
        end

        relpath = generate_relpath(params['file'])

        bytes_wrote = Attache.cache.write(relpath, request.body)
        if bytes_wrote == 0
          return [500, headers_with_cors.merge('X-Exception' => 'Local file failed'), []]
        end

        file = Attache.cache.read(relpath)
        begin
          fulldir = file.path
          if Attache.storage && Attache.bucket
            storage_files.create(Attache.file_options.merge({
              key: File.join(*Attache.remotedir, relpath),
              body: file,
            }))
          end
          [200, headers_with_cors.merge('Content-Type' => 'text/json'), [{
            path:         relpath,
            content_type: content_type_of(fulldir),
            geometry:     geometry_of(fulldir),
          }.to_json]]
        ensure
          file.close unless file.closed?
        end
      when 'OPTIONS'
        [200, headers_with_cors, []]
      else
        [400, headers_with_cors, []]
      end
    else
      @app.call(env)
    end
  rescue Exception
    Attache.logger.error $@
    Attache.logger.error $!
    [500, { 'X-Exception' => $!.to_s }, []]
  end

  private

    def generate_relpath(basename)
      File.join(*SecureRandom.hex.scan(/\w\w/), basename)
    end

    def headers_with_cors
      {
        'Access-Control-Allow-Origin' => '*',
        'Access-Control-Allow-Methods' => 'POST, PUT',
        'Access-Control-Allow-Headers' => 'Content-Type',
      }.merge(JSON.parse(ENV.fetch('UPLOAD_HEADERS') { '{}' }))
    end

    def sha1_digest
      @sha1_digest ||= OpenSSL::Digest.new('sha1')
    end

    def hmac_for(content)
      OpenSSL::HMAC.hexdigest(sha1_digest, Attache.secret_key, content)
    end

    def hmac_valid?(params)
      params['uuid'] &&
      params['hmac']  &&
      params['expiration'] &&
      Time.at(params['expiration'].to_i) > Time.now &&
      Rack::Utils.secure_compare(params['hmac'], hmac_for("#{params['uuid']}#{params['expiration']}"))
    end
end
