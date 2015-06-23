require 'digest/sha1'

class Attache::ResizeJob
  def perform(closed_file, target_geometry_string, extension)
    t = Time.now
    Attache.logger.info "[POOL] start"
    thumbnail = thumbnail_for(closed_file: closed_file, target_geometry_string: target_geometry_string, extension: extension)
    thumbnail.instance_variable_set('@basename', thumbnail.instance_variable_get('@basename').gsub(/[^\w\.]/, '_'))
    thumbnail.make.tap do
      Attache.logger.info "[POOL] done in #{Time.now - t}s"
    end
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    closed_file
  end

  private

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
