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
    Paperclip::GeometryDetector.new(fullpath).make
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    # best effort only
  end

  def filesize_of(fullpath)
    File.stat(fullpath).size
  end
end
