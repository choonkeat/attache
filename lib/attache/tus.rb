class Attache::Tus
  LENGTH_KEYS   = %w[Upload-Length   Entity-Length]
  OFFSET_KEYS   = %w[Upload-Offset   Offset]
  METADATA_KEYS = %w[Upload-Metadata Metadata]

  attr_accessor :env, :config

  def initialize(env, config)
    @env = env
    @config = config
  end

  def header_value(keys)
    value = nil
    keys.find {|k| value = env["HTTP_#{k.gsub('-', '_').upcase}"]}
    value
  end

  def upload_length
    header_value LENGTH_KEYS
  end

  def upload_offset
    header_value OFFSET_KEYS
  end

  def upload_metadata
    value = header_value METADATA_KEYS
    Hash[*value.split(/[, ]/)].inject({}) do |h, (k, v)|
      h.merge(k => Base64.decode64(v))
    end
  end

  def resumable_version
    header_value ["Tus-Resumable"]
  end

  def headers_with_cors(headers = {}, offset: nil)
    tus_headers = {
      "Access-Control-Allow-Methods" => "PATCH",
      "Access-Control-Allow-Headers" => "Tus-Resumable, #{LENGTH_KEYS.join(', ')}, #{METADATA_KEYS.join(', ')}, #{OFFSET_KEYS.join(', ')}",
      "Access-Control-Expose-Headers" => "Location, #{OFFSET_KEYS.join(', ')}",
    }
    OFFSET_KEYS.each do |k|
      tus_headers[k] = offset
    end if offset

    # append
    tus_headers.inject(config.headers_with_cors.merge(headers)) do |sum, (k, v)|
      sum.merge(k => [*sum[k], v].join(', '))
    end
  end
end
