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

        dataprefix = request.body.read(5).tap { request.body.rewind }
        request_body = (dataprefix == 'data:' ? StringIO.new(split_base64(request.body.read)[:data]) : request.body)
        bytes_wrote = Attache.cache.write(cachekey, request_body)
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

  def split_base64(encoded)
    encoded.gsub!(/\n/,'')
    if encoded.match(%r{^data:(.*?);(.*?),(.*)$})
      {
        type: $1,
        encoder: $2,
        data: Base64.decode64($3),
        extension: $1.split('/')[1]
      }
    end
  end
end
