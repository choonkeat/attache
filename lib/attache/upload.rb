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
      when 'POST', 'PUT'
        if Attache.secret_key
          if params['uuid'] &&
             params['hmac']  &&
             params['expiration'] &&
             Time.at(params['expiration'].to_i) > Time.now &&
             Rack::Utils.secure_compare(params['hmac'], hmac_for("#{params['uuid']}#{params['expiration']}"))
            # okay
          else
            return [401, headers_with_cors.merge('X-Exception' => 'Authorization failed'), []]
          end
        end

        relpath = generate_relpath(params['file'])
        fulldir = File.join(Attache.localdir, relpath).tap {|p| FileUtils.mkdir_p(File.dirname(p)) }

        unless local_save(fulldir, request.body)
          return [500, headers_with_cors.merge('X-Exception' => 'Local file failed'), []]
        end
        if Attache.storage && Attache.bucket
          Attache.storage.put_object(Attache.bucket, File.join(*Attache.remotedir, relpath), File.open(fulldir))
        end

        [200, headers_with_cors.merge('Content-Type' => 'text/json'), [{
          path:         relpath,
          content_type: content_type_of(fulldir),
          geometry:     geometry_of(fulldir),
        }.to_json]]
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

    def local_save(fulldir, io)
      open(fulldir, 'wb') {|f| f.write(io.read)}
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

end
