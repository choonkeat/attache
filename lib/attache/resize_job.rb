class Attache::ResizeJob
  def perform(closed_file, geometry, extension)
    Attache.logger.info "[POOL] start"
    thumbnail = Paperclip::Thumbnail.new(closed_file, geometry: geometry, format: extension)
    thumbnail.instance_variable_set('@basename', thumbnail.instance_variable_get('@basename').gsub(/[^\w\.]/, '_'))
    thumbnail.make.tap do
      Attache.logger.info "[POOL] done"
    end
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    closed_file
  end
end
