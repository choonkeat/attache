class Attache::UploadUrl < Attache::Base
  def initialize(app)
    @app = app
  end

  def _call(env, config)
    case env['PATH_INFO']
    when '/upload_url'

      # always pretend to be `POST /upload`
      env['PATH_INFO'] = '/upload'
      env['REQUEST_METHOD'] = 'POST'

      request  = Rack::Request.new(env)
      params   = request.params
      return config.unauthorized unless config.authorized?(params)

      if params['url']
        file, filename, content_type = download_file(params['url'])
        filename = "index" if filename == '/'

        env['CONTENT_TYPE'] = content_type || content_type_of(file.path)
        env['rack.request.query_hash'] = (env['rack.request.query_hash'] || {}).merge('file' => filename)
        env['rack.input'] = file
      end
    end
    @app.call(env)
  end

  MAX_DEPTH = 30
  def download_file(url, depth = 0)
    raise Net::HTTPError, "Too many redirects" if depth > MAX_DEPTH
    Attache.logger.info "Upload GET #{url}"

    if url.match /\Adata:([^;,]+|)(;base64|),/
      # data:[<mediatype>][;base64],<data>
      # http://tools.ietf.org/html/rfc2397

      data = URI.decode(url[url.index(',')+1..-1])
      data = Base64.decode64(data) if $2 == ';base64'
      content_type = ($1 == '' ? "text/plain" : $1)
      filename = "data.#{content_type.gsub(/\W+/, '.')}"
      return [StringIO.new(data), filename, content_type]
    end

    uri = uri.kind_of?(URI::Generic) ? url : URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'
    req = Net::HTTP::Get.new(uri.request_uri)
    req.initialize_http_header({"User-Agent" => ENV['USER_AGENT']}) if ENV['USER_AGENT']
    req.basic_auth(uri.user, uri.password) if uri.user || uri.password
    res = http.request(req)
    case res.code
    when /\A30[1,2]\z/
      download_file URI.join(url, res['Location']).to_s, depth + 1

    when /\A2\d\d\z/
      f = Tempfile.new(["upload_url", File.extname(uri.path)])
      f.write(res.body)
      f.close
      [f.tap(&:open), File.basename(uri.path)]

    else
      raise Net::HTTPError, "Failed #{res.code}"
    end
  end
end
