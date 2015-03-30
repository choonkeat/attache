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
    @storage_files ||= Attache::Storage.new
  end

  def filesize_of(fullpath)
    File.stat(fullpath).size
  end

  def headers_with_cors
    {
      'Access-Control-Allow-Origin' => '*',
      'Access-Control-Allow-Methods' => 'POST, PUT',
      'Access-Control-Allow-Headers' => 'Content-Type',
    }.merge(JSON.parse(ENV.fetch('UPLOAD_HEADERS') { '{}' }))
  end

  def sha1_digest
    @sha1_digest ||= OpenSSL::Digest.new('sha1')
  end

  def hmac_for(content)
    OpenSSL::HMAC.hexdigest(sha1_digest, Attache.secret_key, content)
  end

  def hmac_valid?(params)
    params['uuid'] &&
    params['hmac']  &&
    params['expiration'] &&
    Time.at(params['expiration'].to_i) > Time.now &&
    Rack::Utils.secure_compare(params['hmac'], hmac_for("#{params['uuid']}#{params['expiration']}"))
  end
end
