require 'digest/sha1'
require 'stringio'

class Attache::ResizeJob
  def perform(target_geometry_string, basename, relpath, vhosts, env, t = Time.now)
    closed_file = yield
    return StringIO.new if closed_file.try(:size).to_i == 0

    extension = basename.split(/\W+/).last
    Attache.logger.info "[POOL] start"
    return make_nonimage_preview(closed_file, basename) if ['pdf', 'txt'].include?(extension.to_s.downcase)

    thumbnail = thumbnail_for(closed_file: closed_file, target_geometry_string: target_geometry_string, extension: extension)
    thumbnail.instance_variable_set('@basename', make_safe_filename(thumbnail.instance_variable_get('@basename')))
    thumbnail.make
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    make_nonimage_preview(closed_file, basename)
  ensure
    Attache.logger.info "[POOL] done in #{Time.now - t}s"
  end

  private

    BOLD_FONT_FILE = ENV.fetch('FONT_FILE', File.join(Attache.publicdir, "vendor/roboto/Roboto-Medium.ttf"))
    THIN_FONT_FILE = ENV.fetch('FONT_FILE', File.join(Attache.publicdir, "vendor/roboto/Roboto-Light.ttf"))
    BORDER_SIZE = ENV.fetch('BORDER_SIZE', "3")
    FG_COLOR = ENV.fetch('FG_COLOR', "#ffffff")
    BG_COLOR = ENV.fetch('BG_COLOR', "#dddddd")
    EXT_COLOR = ENV.fetch('EXT_COLOR', "#333333")
    TXT_SIZE = ENV.fetch('TXT_SIZE', "12")
    PREVIEW_SIZE = ENV.fetch('PREVIEW_SIZE', '96x')

    def make_nonimage_preview(closed_file, basename)
      t = Time.now
      Attache.logger.info "[POOL] start nonimage preview"
      output_file = Tempfile.new(["preview", ".png"]).tap(&:close)
      cmd = case basename
      when /\.pdf$/i
        "convert -size #{PREVIEW_SIZE.inspect} #{closed_file.path.inspect}[0] -thumbnail #{PREVIEW_SIZE.inspect} -font #{BOLD_FONT_FILE.inspect}"
      else
        "convert -size #{PREVIEW_SIZE.inspect} \\( -gravity center -font #{BOLD_FONT_FILE.inspect} -fill #{EXT_COLOR.inspect} label:'#{make_safe_filename(basename).split(/\W+/).last}' \\)"
      end + " -bordercolor #{FG_COLOR.inspect} -border #{BORDER_SIZE} -background #{BG_COLOR.inspect} -gravity center -font #{THIN_FONT_FILE.inspect} -pointsize 12 -set caption #{basename.inspect} -polaroid 0 #{output_file.path.inspect}"
      Attache.logger.info cmd
      system cmd
      File.new(output_file.path)
    ensure
      Attache.logger.info "[POOL] done nonimage preview in #{Time.now - t}s"
    end

    def make_safe_filename(str)
      str.to_s.gsub(/[^\w\.]/, '_')
    end

    def thumbnail_for(closed_file:, target_geometry_string:, extension:, max: 2048)
      convert_options = '-interlace Plane' if %w(jpg jpeg).include?(extension.to_s.downcase)
      thumbnail = Paperclip::Thumbnail.new(closed_file, geometry: target_geometry_string, format: extension, convert_options: convert_options)
      current_geometry = current_geometry_for(thumbnail)
      target_geometry = Paperclip::GeometryParser.new(target_geometry_string).make
      if target_geometry.larger <= max && current_geometry.larger > max
        # optimization:
        #  when users upload "super big files", we can speed things up
        #  by working from a "reasonably large 2048x2048 thumbnail" (<2 seconds)
        #  instead of operating on the original (>10 seconds)
        #  we store this reusably in Attache.cache to persist reboot, but not uploaded to cloud
        working_geometry = "#{max}x#{max}>"
        working_file = Attache.cache.fetch(Digest::SHA1.hexdigest(working_geometry + closed_file.path)) do
          Attache.logger.info "[POOL] generate working_file"
          Paperclip::Thumbnail.new(closed_file, geometry: working_geometry, format: extension).make
        end
        Attache.logger.info "[POOL] use working_file #{working_file.path}"
        thumbnail = Paperclip::Thumbnail.new(working_file.tap(&:close), geometry: target_geometry_string, format: extension, convert_options: convert_options)
      end
      thumbnail
    end

    # allow stub in spec
    def current_geometry_for(thumbnail)
      thumbnail.current_geometry.tap(&:auto_orient)
    end

end
