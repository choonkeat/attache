class Attache::Delete < Attache::Base
  def initialize(app)
    @app = app
  end

  def _call(env, config)
    case env['PATH_INFO']
    when '/delete'
      request  = Rack::Request.new(env)
      params   = request.params
      return config.unauthorized unless config.authorized?(params)

      threads = []
      params['paths'].to_s.split("\n").each do |relpath|
        if Attache.cache
          threads << Thread.new do
            Attache.logger.info "DELETING local #{relpath}"
            cachekey = File.join(request_hostname(env), relpath)
            Attache.cache.delete(cachekey)
          end
        end
        if config.storage && config.bucket
          threads << Thread.new do
            Attache.logger.info "DELETING remote #{relpath}"
            config.async(:storage_destroy, relpath: relpath)
          end
        end
        if config.backup
          threads << Thread.new do
            Attache.logger.info "DELETING backup #{relpath}"
            config.backup.async(:storage_destroy, relpath: relpath)
          end
        end
      end
      threads.each(&:join)
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
