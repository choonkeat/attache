require 'digest/sha1'

class Attache::ResizeJob
  def perform(closed_file, target_geometry_string, extension, basename)
    t = Time.now
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

    FONT_FILE = ENV.fetch('FONT_FILE', `convert -list font | grep ttf | head -n 1 | while read key value; do echo $value; done`.chomp)
    BORDER_SIZE = ENV.fetch('BORDER_SIZE', "3")
    FG_COLOR = ENV.fetch('FG_COLOR', "#f9f9f9")
    BG_COLOR = ENV.fetch('BG_COLOR', "#888888")
    TXT_SIZE = ENV.fetch('TXT_SIZE', "12")
    PREVIEW_SIZE = ENV.fetch('PREVIEW_SIZE', '96x')

    def make_nonimage_preview(closed_file, basename)
      t = Time.now
      Attache.logger.info "[POOL] start nonimage preview"
      output_file = Tempfile.new(["preview", ".png"]).tap(&:close)
      cmd = case basename
      when /\.pdf$/i
        "convert #{closed_file.path.inspect}[0] -thumbnail #{PREVIEW_SIZE.inspect}"
      else
        "convert -size #{PREVIEW_SIZE.inspect} \\( -gravity center -font #{FONT_FILE.inspect} -border 10 -bordercolor #{FG_COLOR.inspect} -background #{FG_COLOR.inspect} label:'.#{make_safe_filename(basename).split(/\W+/).last}' \\)"
      end + " -bordercolor #{FG_COLOR.inspect} -border #{BORDER_SIZE} -background #{BG_COLOR.inspect} -pointsize 12 -set caption #{basename.inspect} -polaroid 0 #{output_file.path.inspect}"
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
      thumbnail = Paperclip::Thumbnail.new(closed_file, geometry: target_geometry_string, format: extension)
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
        thumbnail = Paperclip::Thumbnail.new(working_file.tap(&:close), geometry: target_geometry_string, format: extension)
      end
      thumbnail
    end

    # allow stub in spec
    def current_geometry_for(thumbnail)
      thumbnail.current_geometry.tap(&:auto_orient)
    end

end
