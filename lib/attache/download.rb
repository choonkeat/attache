class Attache::Download < Attache::Base
  def initialize(app)
    @app = app
  end

  def call(env)
    case env['PATH_INFO']
    when %r{\A/view/}
      parse_path_info(env['PATH_INFO']['/view/'.length..-1]) do |dirname, geometry, basename, relpath|

        file = begin
          Attache.cache.read(relpath).tap(&:close)
        rescue Errno::ENOENT
        end

        file ||= begin
          if Attache.storage && Attache.bucket
            remote_src_dir = File.join(*Attache.remotedir, dirname, basename)
            if remote_object = Attache.storage.get_object(Attache.bucket, remote_src_dir)
              Attache.cache.write(relpath, StringIO.new(remote_object.body))
              Attache.cache.read(relpath).tap(&:close)
            end
          end
        rescue Excon::Errors
          Attache.logger.error $@
          Attache.logger.error $!
        end

        unless file
          return [404, JSON.parse(download_headers), []]
        end

        thumbnail = if geometry == 'original'
          file
        else
          extension = basename.split(/\W+/).last
          make_thumbnail_for(file, geometry, extension)
        end

        headers = {
          'Content-Type' => content_type_of(thumbnail.path),
        }.merge(JSON.parse(download_headers))

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
      yield dirname, Attache.geometry_alias[geometry] || geometry, basename, relpath
    end

    def download_headers
      ENV.fetch('DOWNLOAD_HEADERS') { '{}' }
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
