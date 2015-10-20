class Attache::Tus::Upload < Attache::Base
  def initialize(app)
    @app = app
  end

  def _call(env, config)
    case env['PATH_INFO']
    when '/tus/files'
      tus = ::Attache::Tus.new(env, config)
      params = params_of(env) # avoid unnecessary `invalid byte sequence in UTF-8` on `request.params`

      case env['REQUEST_METHOD']
      when 'POST'
        if positive_number?(tus.upload_length)
          relpath = generate_relpath(Attache::Upload.sanitize(tus.upload_metadata['filename'] || params['file']))
          cachekey = File.join(request_hostname(env), relpath)

          bytes_wrote = Attache.cache.write(cachekey, StringIO.new)
          uri = URI.parse(Rack::Request.new(env).url)
          uri.query = (uri.query ? "#{uri.query}&" : '') + "relpath=#{CGI.escape relpath}"
          [201, tus.headers_with_cors('Location' => uri.to_s), []]
        else
          [400, tus.headers_with_cors('X-Exception' => "Bad upload length"), []]
        end

      when 'PATCH'
        relpath = params['relpath']
        cachekey = File.join(request_hostname(env), relpath)
        http_offset = tus.upload_offset
        if positive_number?(env['CONTENT_LENGTH']) &&
           positive_number?(http_offset) &&
           (env['CONTENT_TYPE'] == 'application/offset+octet-stream') &&
           tus.resumable_version.to_s == '1.0.0' &&
           current_offset(cachekey) >= http_offset.to_i

          append_to(cachekey, http_offset, env['rack.input'])

          [200,
            tus.headers_with_cors({'Content-Type' => 'text/json'}, offset: current_offset(cachekey)),
            [json_of(relpath, cachekey)],
          ]
        else
          [400, tus.headers_with_cors('X-Exception' => 'Bad headers'), []]
        end

      when 'OPTIONS'
        [201, tus.headers_with_cors, []]

      when 'HEAD'
        relpath = params['relpath']
        cachekey = File.join(request_hostname(env), relpath)
        [200,
          tus.headers_with_cors({'Content-Type' => 'text/json'}, offset: current_offset(cachekey)),
          [json_of(relpath, cachekey)],
        ]

      when 'GET'
        relpath = params['relpath']
        uri = URI.parse(Rack::Request.new(env).url)
        uri.query = nil
        uri.path = File.join('/view', File.dirname(relpath), 'original', File.basename(relpath))
        [302, tus.headers_with_cors('Location' => uri.to_s), []]
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

  private

    def current_offset(cachekey)
      filesize_of path_of(cachekey)
    end

    def append_to(cachekey, offset, io)
      f = File.open(path_of(cachekey), 'r+b')
      f.sync = true
      f.seek(offset.to_i)
      f.write(io.read)
    ensure
      f.close
    end

    def positive_number?(value)
      (value.to_s == "0" || value.to_i > 0)
    end

end
