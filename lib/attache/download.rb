class Attache::Download < Attache::Base
  def initialize(app)
    @app = app
  end

  def call(env)
    case env['PATH_INFO']
    when %r{\A/view/}
      parse_path_info(env['PATH_INFO']['/view/'.length..-1]) do |dirname, geometry, basename, dst_dir|
        unless File.exists?(dst_dir)
          src_dir = File.join(Attache.localdir, dirname, basename)
          if Attache.storage && Attache.bucket && (! File.exists?(src_dir))
            remote_src_dir = File.join(*Attache.remotedir, dirname, basename)
            remote_object = Attache.storage.get_object(Attache.bucket, remote_src_dir)
            FileUtils.mkdir_p(File.dirname(src_dir))
            open(src_dir, 'wb') {|f| f.write(remote_object.body) }
          end
          if File.exists?(src_dir)
            dst_dir = transform_local_file(src_dir, geometry, dst_dir)
          else
            return [404, JSON.parse(ENV.fetch('DOWNLOAD_HEADERS') { '{}' }), []]
          end
        end

        headers = {
          'Content-Type' => Paperclip::ContentTypeDetector.new(dst_dir).detect,
        }.merge(JSON.parse(ENV.fetch('DOWNLOAD_HEADERS') { '{}' }))
        [200, headers, Attache::FileResponseBody.new(File.new(dst_dir))]
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
      dst_dir  = File.join(Attache.localdir, dirname, sanitize_geometry_path(geometry), basename)
      yield dirname, Attache.geometry_alias[geometry] || geometry, basename, dst_dir
    end

    def sanitize_geometry_path(geometry)
      geometry.gsub(/\W+/, '') + '-' + Digest::SHA1.hexdigest(geometry)
    end

    def transform_local_file(src, geometry, dst)
      extension = src.split(/\W+/).last
      thumb = Paperclip::Thumbnail.new(File.new(src), geometry: geometry, format: extension)
      result = thumb.make
      FileUtils.mkdir_p(File.dirname(dst))
      File.rename result.path, dst
      dst
    end

end
