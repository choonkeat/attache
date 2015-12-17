require 'connection_pool'

class Attache::Download < Attache::Base
  OUTPUT_EXTENSIONS = %w[png jpg jpeg gif]
  RESIZE_JOB_POOL = ConnectionPool.new(JSON.parse(ENV.fetch('RESIZE_POOL') { '{ "size": 2, "timeout": 60 }' }).symbolize_keys) { Attache::ResizeJob.new }

  def initialize(app)
    @app = app
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

        file = begin
          cachekey = File.join(request_hostname(env), relpath)
          Attache.cache.fetch(cachekey) do
            get_first_result_async(vhosts.inject({}) {|sum,(k,v)|
              if v
                sum.merge("#{k} #{relpath}" => lambda {
                  begin
                    v.storage_get(relpath: relpath)
                  rescue Exception
                    Attache.logger.info "[POOL] not found #{k} #{relpath}"
                    nil
                  end
                })
              else
                sum
              end
            })
          end
        rescue Exception # Errno::ECONNREFUSED, OpenURI::HTTPError, Excon::Errors, Fog::Errors::Error
          Attache.logger.error "ERROR REFERER #{env['HTTP_REFERER'].inspect}"
          nil
        end

        unless file
          return [404, config.download_headers, []]
        end

        thumbnail = case geometry
        when 'original', *vhosts.keys
          file
        else
          extension = basename.split(/\W+/).last
          extension = OUTPUT_EXTENSIONS.first unless OUTPUT_EXTENSIONS.index(extension.to_s.downcase)
          make_thumbnail_for(file.tap(&:close), geometry, extension)
        end

        headers = {
          'Content-Type' => content_type_of(thumbnail.path),
        }.merge(config.download_headers)

        [200, headers, rack_response_body_for(thumbnail)].tap do
          unless file == thumbnail # cleanup
            File.unlink(thumbnail.path) rescue Errno::ENOENT
          end
        end
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

    def make_thumbnail_for(file, geometry, extension)
      Attache.logger.info "[POOL] new job"
      RESIZE_JOB_POOL.with do |job|
        job.perform(file, geometry, extension)
      end
    end

    def get_first_result_async(name_code_pairs)
      result = nil
      threads = name_code_pairs.collect {|name, code|
        Thread.new do
          Thread.handle_interrupt(BasicObject => :on_blocking) { # if killed
            if result
              # war over
            elsif current_result = code.call
              result = current_result
              (threads - [Thread.current]).each(&:kill)        # kill siblings
              Attache.logger.info "[POOL] found #{name.inspect}"
            else
              # no contribution
            end
          }
        end
      }
      threads.each(&:join)
      result
    end
end
