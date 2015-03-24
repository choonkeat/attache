class Attache::Delete < Attache::Base
  def initialize(app)
    @app = app
  end

  def call(env)
    case env['PATH_INFO']
    when '/delete'
      request  = Rack::Request.new(env)
      params   = request.params

      if Attache.secret_key
        unless hmac_valid?(params)
          return [401, headers_with_cors.merge('X-Exception' => 'Authorization failed'), []]
        end
      end

      result = Hash(local: {}, remote: {})
      params['paths'].to_s.split("\n").each do |relpath|
        Attache.logger.info "DELETING local #{relpath}"
        result[:local][relpath] = Attache.cache.delete(relpath)
        if Attache.storage && Attache.bucket
          Attache.logger.info "DELETING remote #{relpath}"
          result[:remote][relpath] = storage_files.new(Attache.file_options.merge({
            key: File.join(*Attache.remotedir, relpath),
          })).destroy
        end
      end
      [200, headers_with_cors.merge('Content-Type' => 'text/json'), [result.to_json]]
    else
      @app.call(env)
    end
  rescue Exception
    Attache.logger.error $@
    Attache.logger.error $!
    [500, { 'X-Exception' => $!.to_s }, []]
  end
end
