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

        if params.has_key? 'data'

          base_64_encoded_data = params['data']
          data_index = base_64_encoded_data.index('base64') + 7
          data_format = base_64_encoded_data.match(/image\/(\w+)/)[1]
          filedata = base_64_encoded_data[data_index..-1]
          decoded_image = Base64.decode64(filedata)

          filename = "#{Time.now.to_i}.#{data_format}"

          relpath = generate_relpath(Attache::Upload.sanitize filename)
          cachekey = File.join(request_hostname(env), relpath)

          bytes_wrote = Attache.cache.write(cachekey, StringIO.new(decoded_image))
        else
          relpath = generate_relpath(Attache::Upload.sanitize params['file'])
          cachekey = File.join(request_hostname(env), relpath)
          bytes_wrote = Attache.cache.write(cachekey, request.body)
        end

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
