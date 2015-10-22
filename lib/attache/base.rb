class Attache::Base
  def call(env)
    if vhost = vhost_for(request_hostname(env))
      dup._call(env, vhost)
    else
      @app.call(env)
    end
  end

  def vhost_for(host)
    Attache::VHost.new(Attache.vhost[host])
  end

  def request_hostname(env)
    env['HTTP_X_FORWARDED_HOST'] || env['HTTP_HOST'] || "unknown.host"
  end

  def content_type_of(fullpath)
    Paperclip::ContentTypeDetector.new(fullpath).detect
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    # best effort only
  end

  def geometry_of(fullpath)
    Paperclip::Geometry.from_file(fullpath).tap(&:auto_orient).to_s
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    # best effort only
  end

  def filesize_of(fullpath)
    File.stat(fullpath).size
  end

  def params_of(env)
    env['QUERY_STRING'].to_s.split('&').inject({}) do |sum, pair|
      k, v = pair.split('=').collect {|s| CGI.unescape(s) }
      sum.merge(k => v)
    end
  end

  def path_of(cachekey)
    Attache.cache.send(:key_file_path, cachekey)
  end

  def rack_response_body_for(file)
    Attache::FileResponseBody.new(file)
  end

  def generate_relpath(basename)
    File.join(*SecureRandom.hex.scan(/\w\w/), basename)
  end

  def json_of(relpath, cachekey)
    filepath = path_of(cachekey)
    {
      path:         relpath,
      content_type: content_type_of(filepath),
      geometry:     geometry_of(filepath),
      bytes:        filesize_of(filepath),
    }.to_json
  end

end
