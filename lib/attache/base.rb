class Attache::Base
  def content_type_of(fullpath)
    Paperclip::ContentTypeDetector.new(fullpath).detect
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    # best effort only
  end

  def geometry_of(fullpath)
    Paperclip::GeometryDetector.new(fullpath).make
  rescue Paperclip::Errors::NotIdentifiedByImageMagickError
    # best effort only
  end
end
