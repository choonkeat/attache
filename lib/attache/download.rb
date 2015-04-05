class Attache::Download < Attache::Base
  def initialize(app)
    @app = app
  end

  def _call(env, config)
    case env['PATH_INFO']
    when %r{\A/view/}
      parse_path_info(env['PATH_INFO']['/view/'.length..-1]) do |dirname, geometry, basename, relpath|
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

        thumbnail = if geometry == 'original'
          file
        else
          extension = basename.split(/\W+/).last
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
      thumbnail = Paperclip::Thumbnail.new(file, geometry: geometry, format: extension)
      # weird output filenames can confuse imagemagick; sanitizing output basename
      thumbnail.instance_variable_set('@basename', thumbnail.instance_variable_get('@basename').gsub(/[^\w\.]/, '_'))
      thumbnail.make
    rescue Paperclip::Errors::NotIdentifiedByImageMagickError
      file
    end

    def rack_response_body_for(file)
      Attache::FileResponseBody.new(file)
    end

end
