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

  def storage_files
    @storage_files ||= Attache.storage.directories.get(Attache.bucket).files
  end

  def filesize_of(fullpath)
    File.stat(fullpath).size
  end
end
