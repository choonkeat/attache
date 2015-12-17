class Attache::Upload < Attache::Base
  def initialize(app)
    @app = app
  end

  def _call(env, config)
    case env['PATH_INFO']
    when '/upload'
      case env['REQUEST_METHOD']
      when 'POST', 'PUT', 'PATCH'
        request  = Rack::Request.new(env)
        params   = request.params
        return config.unauthorized unless config.authorized?(params)

        relpath = generate_relpath(Attache::Upload.sanitize params['file'])
        cachekey = File.join(request_hostname(env), relpath)

        bytes_wrote = Attache.cache.write(cachekey, request.body)
        if bytes_wrote == 0
          return [500, config.headers_with_cors.merge('X-Exception' => 'Local file failed'), []]
        else
          Attache.logger.info "[Upload] received #{bytes_wrote} #{cachekey}"
        end

        config.storage_create(relpath: relpath, cachekey: cachekey) if config.storage && config.bucket

        [200, config.headers_with_cors.merge('Content-Type' => 'text/json'), [json_of(relpath, cachekey)]]
      when 'OPTIONS'
        [200, config.headers_with_cors, []]
      else
        [400, config.headers_with_cors, []]
      end
    else
      @app.call(env)
    end
  end

  def self.sanitize(filename)
    filename.to_s.gsub(/\%/, '_')
  end
end
