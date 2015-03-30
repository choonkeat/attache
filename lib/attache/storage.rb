class Attache::Storage
  def api
    Attache.storage.directories.get(Attache.bucket).files
  end

  def create(options)
    api.create(Attache.file_options.merge(options))
  end

  def get(path)
    tmpfile = Tempfile.new('fog')
    bool = api.get(path) do |data, remaining, content_length|
      tmpfile.syswrite data
    end
    yield tmpfile.tap(&:rewind) if bool
  ensure
    tmpfile.close unless tmpfile.closed?
    tmpfile.unlink
  end

  def destroy(options)
    api.new(Attache.file_options.merge(options)).destroy
  end
end
