require 'base64'
require 'connection_pool'
require 'json'
require 'rack'
require 'openssl'

class Attache::Download < Attache::Base
  RESIZE_JOB_POOL = ConnectionPool.new(JSON.parse(ENV.fetch('RESIZE_POOL') { '{ "size": 2, "timeout": 60 }' }).symbolize_keys) { Attache::ResizeJob.new }

  def initialize(app)
    @app = app
    @mutexes = {}
  end

  def _call(env, config)
    case env['PATH_INFO']
    when %r{\A/view/}
      vhosts = {}
      vhosts[ENV.fetch('REMOTE_GEOMETRY') { 'remote' }] = config.storage && config.bucket && config
      vhosts[ENV.fetch('BACKUP_GEOMETRY') { 'backup' }] = config.backup

      parse_path_info(env['PATH_INFO']['/view/'.length..-1]) do |dirname, instruction_string, hmac, basename, relpath|
        return config.unauthorized unless authorized?(config, instruction_string, hmac)

        if vhost = vhosts[instruction_string]
          headers = vhost.download_headers.merge({
                      'Location' => vhost.storage_url(relpath: relpath),
                      'Cache-Control' => 'private, no-cache',
                    })
          return [302, headers, []]
        end

        thumbnail = case instruction_string
          when 'original', *vhosts.keys
            get_original_file(relpath, vhosts, env)
          else
            get_thumbnail_file(instruction_string, basename, relpath, vhosts, env)
          end

        return [404, config.download_headers, []] if thumbnail.try(:size).to_i == 0

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

    def authorized?(config, instruction_string, hmac)
      # TODO: need to do something to _ensure_ a public key along with this change?
      our_hmac = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), config.secret_key.to_s, instruction_string)

      Rack::Utils.secure_compare(hmac, our_hmac)
    end

    # path is e.g. "a/b/c/d/e/:instructions/:hmac/:file_name.jpg"
    def parse_path_info(url_path)
      parts = url_path.split("/")

      basename           = CGI.unescape(parts.pop)
      hmac               = CGI.unescape(parts.pop)
      instruction_string = CGI.unescape(parts.pop)
      dirname            = parts.join("/")
      relpath            = File.join(dirname, basename)

      yield dirname, instruction_string, hmac, basename, relpath
    end

    def synchronize(key, &block)
      mutex = @mutexes[key] ||= Mutex.new
      mutex.synchronize(&block)
    ensure
      @mutexes.delete(key)
    end

    def get_thumbnail_file(instruction_string, basename, relpath, vhosts, env)
      instructions = JSON.parse(Base64.urlsafe_decode64(instruction_string))
      cachekey = File.join(request_hostname(env), relpath, instruction_string)

      synchronize(cachekey) do
        tempfile = nil
        Attache.cache.fetch(cachekey) do
          Attache.logger.info "[POOL] new job"
          tempfile = RESIZE_JOB_POOL.with do |job|
            job.perform(instructions, basename) do
              # opens up possibility that job implementation
              # does not require we download original file prior
              get_original_file(relpath, vhosts, env)
            end
          end
        end.tap { File.unlink(tempfile.path) if tempfile.try(:path) }
      end
    end

    def get_original_file(relpath, vhosts, env)
      cachekey = File.join(request_hostname(env), relpath)
      synchronize(cachekey) do
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
      end
    rescue Exception # Errno::ECONNREFUSED, OpenURI::HTTPError, Excon::Errors, Fog::Errors::Error
      Attache.logger.error "ERROR REFERER #{env['HTTP_REFERER'].inspect}"
      nil
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
