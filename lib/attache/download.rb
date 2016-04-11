require 'connection_pool'

class Attache::Download < Attache::Base
  RESIZE_JOB_POOL = ConnectionPool.new(JSON.parse(ENV.fetch('RESIZE_POOL') { '{ "size": 2, "timeout": 60 }' }).symbolize_keys) { Attache::ResizeJob.new }

  def initialize(app)
    @app = app
    @mutexes = {}
  end

  def synchronize(key, &block)
    mutex = @mutexes[key] ||= Mutex.new
    mutex.synchronize(&block)
  ensure
    @mutexes.delete(key)
  end

  def _call(env, config)
    case env['PATH_INFO']
    when %r{\A/view/}
      vhosts = {}
      vhosts[ENV.fetch('REMOTE_GEOMETRY') { 'remote' }] = config.storage && config.bucket && config
      vhosts[ENV.fetch('BACKUP_GEOMETRY') { 'backup' }] = config.backup

      parse_path_info(env['PATH_INFO']['/view/'.length..-1]) do |dirname, geometry, basename, relpath|
        if vhost = vhosts[geometry]
          headers = vhost.download_headers.merge({
                      'Location' => vhost.storage_url(relpath: relpath),
                      'Cache-Control' => 'private, no-cache',
                    })
          return [302, headers, []]
        end

        file = synchronize relpath do
          begin
            cachekey = File.join(request_hostname(env), relpath)
            Attache.cache.fetch(cachekey) do
              name_with_vhost_pairs = vhosts.inject({}) { |sum,(k,v)| (v ? sum.merge(k => v) : sum) }
              get_first_result_present_async(name_with_vhost_pairs.collect {|name, vhost|
                lambda { Thread.handle_interrupt(BasicObject => :on_blocking) {
                  begin
                    Attache.logger.info "[POOL] looking for #{name} #{relpath}..."
                    vhost.storage_get(relpath: relpath).tap do |v|
                      Attache.logger.info "[POOL] found #{name} #{relpath} = #{v.inspect}"
                    end
                  rescue Exception
                    Attache.logger.error $!
                    Attache.logger.error $@
                    Attache.logger.info "[POOL] not found #{name} #{relpath}"
                    nil
                  end
                } }
              })
            end
          rescue Exception # Errno::ECONNREFUSED, OpenURI::HTTPError, Excon::Errors, Fog::Errors::Error
            Attache.logger.error "ERROR REFERER #{env['HTTP_REFERER'].inspect}"
            nil
          end
        end

        unless file && file.try(:size).to_i > 0
          return [404, config.download_headers, []]
        end

        thumbnail = synchronize "#{relpath}#{geometry}" do
          case geometry
          when 'original', *vhosts.keys
            file
          else
            cachekey_with_geometry = File.join(request_hostname(env), relpath, geometry)
            tempfile = nil
            Attache.cache.fetch(cachekey_with_geometry) do
              extension = basename.split(/\W+/).last
              tempfile = make_thumbnail_for(file.tap(&:close), geometry, extension, basename)
            end.tap { File.unlink(tempfile.path) if tempfile.try(:path) }
          end
        end

        headers = {
          'Content-Type' => content_type_of(thumbnail.path),
        }.merge(config.download_headers)

        [200, headers, rack_response_body_for(thumbnail)]
      end
    else
      @app.call(env)
    end
  end

  private

    def parse_path_info(geometrypath)
      parts = geometrypath.split('/')
      basename = CGI.unescape parts.pop
      geometry = CGI.unescape parts.pop
      dirname  = parts.join('/')
      relpath  = File.join(dirname, basename)
      yield dirname, geometry, basename, relpath
    end

    def make_thumbnail_for(file, geometry, extension, basename)
      Attache.logger.info "[POOL] new job"
      RESIZE_JOB_POOL.with do |job|
        job.perform(file, geometry, extension, basename)
      end
    end

    # Ref https://gist.github.com/sferik/39831f34eb87686b639c#gistcomment-1652888
    # a bit more complicated because we *want* to ignore falsey result
    def get_first_result_present_async(lambdas)
      return if lambdas.empty? # queue.pop will never happen
      queue = Queue.new
      threads = lambdas.shuffle.collect { |code| Thread.new { queue << [Thread.current, code.call] } }
      until (item = queue.pop).last do
        thread, _ = item
        thread.join # we could be popping `queue` before thread exited
        break unless threads.any?(&:alive?) || queue.size > 0
      end
      threads.each(&:kill)
      _, result = item
      result
    end
end
