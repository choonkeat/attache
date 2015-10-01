class Attache::Upload < Attache::Base
  def initialize(app)
    @app = app
  end

  def _call(env, config)
    case env['PATH_INFO']
    when '/upload'
      request  = Rack::Request.new(env)
      params   = request.params

      case env['REQUEST_METHOD']
      when 'POST', 'PUT', 'PATCH'
        if config.secret_key
          unless config.hmac_valid?(params)
            return [401, config.headers_with_cors.merge('X-Exception' => 'Authorization failed'), []]
          end
        end

        relpath = generate_relpath(Attache::Upload.sanitize params['file'])
        cachekey = File.join(request_hostname(env), relpath)

        bytes_wrote = Attache.cache.write(cachekey, request.body)
        if bytes_wrote == 0
          return [500, config.headers_with_cors.merge('X-Exception' => 'Local file failed'), []]
        end

        if config.storage && config.bucket
          request.body.rewind if request.body.respond_to?(:rewind)
          if Attache.outbox.write(request_hostname(env), relpath, request.body) > 0
            config.async(:storage_create, relpath: relpath, cachekey: cachekey)
          else
            return [500, config.headers_with_cors.merge('X-Exception' => 'Outbox file failed'), []]
          end
        end

        file = Attache.cache.read(cachekey)
        file.close unless file.closed?
        [200, config.headers_with_cors.merge('Content-Type' => 'text/json'), [{
          path:         relpath,
          content_type: content_type_of(file.path),
          geometry:     geometry_of(file.path),
          bytes:        filesize_of(file.path),
        }.to_json]]
      when 'OPTIONS'
        [200, config.headers_with_cors, []]
      else
        [400, config.headers_with_cors, []]
      end
    else
      @app.call(env)
    end
  rescue Exception
    Attache.logger.error $@
    Attache.logger.error $!
    Attache.logger.error "ERROR REFERER #{env['HTTP_REFERER'].inspect}"
    [500, { 'X-Exception' => $!.to_s }, []]
  end

  def self.sanitize(filename)
    filename.to_s.gsub(/\%/, '_')
  end

  private

    def generate_relpath(basename)
      File.join(*SecureRandom.hex.scan(/\w\w/), basename)
    end
end
