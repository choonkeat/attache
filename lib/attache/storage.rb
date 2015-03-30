class Attache::Storage
  def self.api
    Attache.storage.directories.get(Attache.bucket).files
  end

  def create(relpath, options)
    CreateJob.new.async.perform(relpath, options)
  end

  def get(path)
    tmpfile = Tempfile.new('fog')
    bool = self.class.api.get(path) do |data, remaining, content_length|
      tmpfile.syswrite data
    end
    yield tmpfile.tap(&:rewind) if bool
  ensure
    tmpfile.close unless tmpfile.closed?
    tmpfile.unlink
  end

  def destroy(options)
    DeleteJob.new.async.perform(options)
  end

  class CreateJob
    include ::SuckerPunch::Job
    def perform(relpath, options)
      file = Attache.cache.read(relpath)
      Attache::Storage.api.create(Attache.file_options.merge(options).merge(body: file))
      Attache.logger.info "created #{relpath}"
    ensure
      file.close unless file && file.closed?
    end
  end

  class DeleteJob
    include ::SuckerPunch::Job
    def perform(options)
      Attache::Storage.api.new(Attache.file_options.merge(options)).destroy
      Attache.logger.info "deleted #{options.inspect}"
    end
  end
end
