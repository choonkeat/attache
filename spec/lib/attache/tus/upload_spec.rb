require 'spec_helper'

describe Attache::Tus::Upload do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Tus::Upload.new(app) }
  let(:params) { Hash(file: filename) }
  let(:filename) { "Exãmple %#{rand} %20.gif" }
  let(:file) { StringIO.new(IO.binread("spec/fixtures/landscape.jpg"), 'rb') }
  let(:filesize) { File.size "spec/fixtures/landscape.jpg" }
  let(:hostname) { "example.com" }
  let(:create_path) { '/tus/files?' + params.collect {|k,v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}"}.join('&') }
  let(:resume_path) { @location }

  before do
    allow(Attache).to receive(:logger).and_return(Logger.new('/dev/null'))
    allow(Attache).to receive(:localdir).and_return(Dir.tmpdir) # forced, for safety
    allow_any_instance_of(Attache::VHost).to receive(:secret_key).and_return(nil)
    allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(nil)
    allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(nil)
  end

  after do
    FileUtils.rm_rf(Attache.localdir)
  end

  it "should passthrough irrelevant request" do
    code, headers, body = middleware.call Rack::MockRequest.env_for('http://' + hostname, "HTTP_HOST" => hostname)
    expect(code).to eq 200
  end


  def make_request_to(request_uri, headers)
    middleware.call Rack::MockRequest.env_for('http://' + hostname + request_uri, Hash("HTTP_HOST" => hostname, 'HTTP_UPLOAD_METADATA' => "key #{Base64.encode64('value')},filename #{Base64.encode64(filename)}").merge(headers))
  end

  context "tus creation" do
    it "must reject missing HTTP_ENTITY_LENGTH" do
      code, headers, body = make_request_to(create_path, method: 'POST', input: file)
      expect(code).to eq(400)
    end

    it "must reject invalid HTTP_ENTITY_LENGTH" do
      code, headers, body = make_request_to(create_path, method: 'POST', input: file, 'HTTP_ENTITY_LENGTH' => [-1, 'abc'].sample)
      expect(code).to eq(400)
    end

    it "must respond successfully with HTTP 201 + Location header" do
      code, headers, body = make_request_to(create_path, method: 'POST', input: file, 'HTTP_ENTITY_LENGTH' => filesize)
      expect(code).to eq(201)
      expect(headers['Location']).to be_present
    end
  end

  context "with uploaded file" do
    let(:relpath)  { CGI.unescape @location.match(/relpath=([^&]+)/)[1] }
    let(:cachekey) { File.join(hostname, relpath) }
    let(:current_offset) { 3 + rand(10) }

    before do
      code, headers, body = make_request_to(create_path, method: 'POST', input: file, 'HTTP_ENTITY_LENGTH' => filesize)
      expect(code).to eq(201)
      @location = URI.parse(headers['Location']).request_uri
      open(middleware.path_of(cachekey), "a") {|f| f.write('a' * current_offset) }
    end

    context "tus patch" do
      it "must reject invalid HTTP_OFFSET" do
        code, headers, body = make_request_to(resume_path, method: 'PATCH', input: file)
        expect(code).to eq(400)
      end

      it "must reject invalid HTTP_CONTENT_LENGTH" do
        code, headers, body = make_request_to(resume_path, method: 'PATCH', input: file, "HTTP_OFFSET" => 0)
        expect(code).to eq(400)
      end

      it "must reject invalid Content-Type: application/offset+octet-stream" do
        code, headers, body = make_request_to(resume_path, method: 'PATCH', input: file, "HTTP_OFFSET" => 0, "HTTP_CONTENT_LENGTH" => filesize, "CONTENT_TYPE" => ["application/octet-stream", nil].sample)
        expect(code).to eq(400)
      end

      it "must reject invalid Tus-Resumable version" do
        code, headers, body = make_request_to(resume_path, method: 'PATCH', input: file, "HTTP_OFFSET" => 0, "HTTP_CONTENT_LENGTH" => filesize, "CONTENT_TYPE" => "application/offset+octet-stream", "HTTP_TUS_RESUMABLE" => ["0.9.9", "2.0.0"].sample)
        expect(code).to eq(400)
      end

      it "must respond successfully with HTTP 200" do
        code, headers, body = make_request_to(resume_path, method: 'PATCH', input: file, "HTTP_OFFSET" => 0, "HTTP_CONTENT_LENGTH" => filesize, "CONTENT_TYPE" => "application/offset+octet-stream", "HTTP_TUS_RESUMABLE" => "1.0.0")
        expect(headers['X-Exception']).to be_nil
        expect(code).to eq(200)
      end

      it "must accept `offset` smaller or equal to current offset" do
        code, headers, body = make_request_to(resume_path, method: 'PATCH', input: file, "HTTP_OFFSET" => current_offset - [0, 1].sample, "HTTP_CONTENT_LENGTH" => filesize, "CONTENT_TYPE" => "application/offset+octet-stream", "HTTP_TUS_RESUMABLE" => "1.0.0")
        expect(headers['X-Exception']).to be_nil
        expect(code).to eq(200)
      end

      it "must reject `offset` larger than current offset" do
        code, headers, body = make_request_to(resume_path, method: 'PATCH', input: file, "HTTP_OFFSET" => current_offset + 1, "HTTP_CONTENT_LENGTH" => filesize, "CONTENT_TYPE" => "application/offset+octet-stream", "HTTP_TUS_RESUMABLE" => "1.0.0")
        expect(code).to eq(400)
      end

      it "new current offset must be Offset + Content-Length" do
        expect {
          make_request_to(resume_path, method: 'PATCH', input: file, "HTTP_OFFSET" => current_offset, "HTTP_CONTENT_LENGTH" => filesize, "CONTENT_TYPE" => "application/offset+octet-stream", "HTTP_TUS_RESUMABLE" => "1.0.0")
        }.to change {
          middleware.send(:current_offset, cachekey, relpath, config = {})
        }.by(filesize)
      end
    end

    context "tus head" do
      it "must respond successfully with HTTP 200 + Offset header" do
        code, headers, body = make_request_to(resume_path, method: 'HEAD')
        expect(code).to eq(200)
        expect(headers).to eq({
          "Access-Control-Allow-Origin"   => "*",
          "Access-Control-Allow-Methods"  => "POST, PUT, PATCH",
          "Access-Control-Allow-Headers"  => "Content-Type, Tus-Resumable, Upload-Length, Entity-Length, Upload-Metadata, Metadata, Upload-Offset, Offset",
          "Content-Type"                  => "text/json",
          "Access-Control-Expose-Headers" => "Location, Upload-Offset, Offset",
          "Offset"                        => current_offset.to_s,
          "Upload-Offset"                 => current_offset.to_s,
        })
      end
    end

    context "tus get" do
      it "must redirec to attache download url for original geometry" do
        code, headers, body = make_request_to(resume_path, method: 'GET')
        expect(code).to eq(302)
        expect(File.basename headers['Location']).to eq(CGI.escape(Attache::Upload.sanitize filename))
      end
    end
  end
end
