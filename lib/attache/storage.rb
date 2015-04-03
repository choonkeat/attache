class Attache::Storage
  def self.api
    Attache.storage.directories.new(key: Attache.bucket).files
  end

  def create(relpath, options)
    CreateJob.new.async.perform(relpath, options)
  end

  def get(path, &block)
    url = Attache.storage.directories.new(key: Attache.bucket).files.new(key: path).url(Time.now + 60)
    open(url, &block)
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
