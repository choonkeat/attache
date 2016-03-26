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
        params   = request.GET # stay away from parsing body
        return config.unauthorized unless config.authorized?(params)

        relpath = generate_relpath(Attache::Upload.sanitize params['file'])
        cachekey = File.join(request_hostname(env), relpath)

        bytes_wrote = Attache.cache.write(cachekey, cleaned_up(request.body))
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

  private

  def cleaned_up(io)
    prefix = io.read(80).tap { io.rewind }
    case prefix
    when /\Adata:([^;,]+|)(;base64|),/
      # data:[<mediatype>][;base64],<data>
      # http://tools.ietf.org/html/rfc2397
      io.read(prefix.index(',')+1) # discard metadata
      data = URI.decode(io.read)
      data = Base64.decode64(data) if $2 == ';base64'
      StringIO.new(data)
    else
      io
    end
  end
end
