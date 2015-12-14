class Attache::Backup < Attache::Base
  def initialize(app)
    @app = app
  end

  def _call(env, config)
    case env['PATH_INFO']
    when '/backup'
      request  = Rack::Request.new(env)
      params   = request.params
      return config.unauthorized unless config.authorized?(params)

      params['paths'].to_s.split("\n").each do |relpath|
        Attache.logger.info "CONFIRM local #{relpath}"
        cachekey = File.join(request_hostname(env), relpath)
        if config.storage && config.bucket
          Attache.logger.info "CONFIRM remote #{relpath}"
          config.async(:backup_file, relpath: relpath)
        end
      end
      [200, config.headers_with_cors, []]
    else
      @app.call(env)
    end
  rescue Exception
    Attache.logger.error $@
    Attache.logger.error $!
    [500, { 'X-Exception' => $!.to_s }, []]
  end
end
