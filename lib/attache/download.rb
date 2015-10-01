require 'connection_pool'

class Attache::Download < Attache::Base
  REMOTE_GEOMETRY = ENV.fetch('REMOTE_GEOMETRY') { 'remote' }
  OUTPUT_EXTENSIONS = %w[png jpg jpeg gif]
  RESIZE_JOB_POOL = ConnectionPool.new(JSON.parse(ENV.fetch('RESIZE_POOL') { '{ "size": 2, "timeout": 60 }' }).symbolize_keys) { Attache::ResizeJob.new }

  def initialize(app)
    @app = app
  end

  def _call(env, config)
    case env['PATH_INFO']
    when %r{\A/view/}
      parse_path_info(env['PATH_INFO']['/view/'.length..-1]) do |dirname, geometry, basename, relpath|
        if geometry == REMOTE_GEOMETRY && config.storage && config.bucket
          headers = config.download_headers.merge({
                      'Location' => config.storage_url(relpath: relpath),
                      'Cache-Control' => 'private, no-cache',
                    })
          return [302, headers, []]
        end

        file = begin
          cachekey = File.join(request_hostname(env), relpath)
          Attache.cache.fetch(cachekey) do
            config.storage_get(relpath: relpath) if config.storage && config.bucket
          end
        rescue Exception # Errno::ECONNREFUSED, OpenURI::HTTPError, Excon::Errors, Fog::Errors::Error
          Attache.logger.error $@
          Attache.logger.error $!
          nil
        end

        unless file
          return [404, config.download_headers, []]
        end

        thumbnail = if geometry == 'original' || geometry == REMOTE_GEOMETRY
          file
        else
          extension = basename.split(/\W+/).last
          extension = OUTPUT_EXTENSIONS.first unless OUTPUT_EXTENSIONS.index(extension.to_s.downcase)
          make_thumbnail_for(file.tap(&:close), geometry, extension)
        end

        headers = {
          'Content-Type' => content_type_of(thumbnail.path),
        }.merge(config.download_headers)

        [200, headers, rack_response_body_for(thumbnail)].tap do
          unless file == thumbnail # cleanup
            File.unlink(thumbnail.path) rescue Errno::ENOENT
          end
        end
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

    def parse_path_info(geometrypath)
      parts = geometrypath.split('/')
      basename = CGI.unescape parts.pop
      geometry = CGI.unescape parts.pop
      dirname  = parts.join('/')
      relpath  = File.join(dirname, basename)
      yield dirname, geometry, basename, relpath
    end

    def make_thumbnail_for(file, geometry, extension)
      Attache.logger.info "[POOL] new job"
      RESIZE_JOB_POOL.with do |job|
        job.perform(file, geometry, extension)
      end
    end

    def rack_response_body_for(file)
      Attache::FileResponseBody.new(file)
    end

end
