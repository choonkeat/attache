require 'spec_helper'

describe Attache::Upload do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Upload.new(app) }
  let(:params) { {} }
  let(:filename) { "Exãmple %#{rand} %20.gif" }
  let(:file) { StringIO.new(IO.binread("spec/fixtures/landscape.jpg"), 'rb') }
  let(:request_input) { file }
  let(:base64_data) { "data:image/gif;base64," + Base64.encode64(file.read) }
  let(:hostname) { "example.com" }

  before do
    allow(Attache).to receive(:localdir).and_return(Dir.tmpdir) # forced, for safety
    allow_any_instance_of(Attache::VHost).to receive(:secret_key).and_return(nil)
  end

  after do
    FileUtils.rm_rf(Attache.localdir)
  end

  it "should passthrough irrelevant request" do
    code, headers, body = middleware.call Rack::MockRequest.env_for('http://' + hostname, "HTTP_HOST" => hostname)
    expect(code).to eq 200
  end

  context "uploading" do
    let(:params) { Hash(file: filename) }

    subject { proc { middleware.call Rack::MockRequest.env_for('http://' + hostname + '/upload?' + params.collect {|k,v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}"}.join('&'), method: 'PUT', input: request_input, "HTTP_HOST" => hostname) } }

    it 'should respond successfully with json' do
      code, headers, body = subject.call
      expect(code).to eq(200)
      expect(headers['Content-Type']).to eq('text/json')
      JSON.parse(body.join('')).tap do |json|
        expect(json).to be_has_key('path')
        expect(json['geometry']).to eq('4x3')
        expect(json['bytes']).to eq(425)
        expect(json['signature']).to eq(nil)
      end
    end

    it 'should wrote to cache with Attache::Upload.sanitize(params[:file]) as filename' do
      code, headers, body = subject.call
      json = JSON.parse(body.join(''))
      relpath = json['path']
      expect(relpath).to end_with(Attache::Upload.sanitize params[:file])
      expect(Attache.cache.read(hostname + '/' + relpath).tap(&:close)).to be_kind_of(File)
    end

    # does not support base64/data uri here
    # see upload_url.rb
    context 'base64' do
      context 'base64-encoded image' do
        let!(:request_input) { StringIO.new("data:image/gif;base64," + Base64.encode64(file.read)) }

        it 'should respond identically as when uploading binary' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['geometry']).to eq(nil)
            expect(json['content_type']).to eq('text/plain')
          end
        end
      end

      # various Data URI permutations
      # https://developer.mozilla.org/en-US/docs/Web/HTTP/data_URIs
      context 'simple text/plain data' do
        let!(:request_input) { StringIO.new "data:,Hello%2C%20World!" }

        it 'should decode' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['content_type']).to eq('text/plain')
            expect(json['bytes']).to eq(23)
          end
        end
      end

      context "base64-encoded version of the above" do
        let!(:request_input) { StringIO.new "data:text/plain;base64,SGVsbG8sIFdvcmxkIQ%3D%3D" }

        it 'should decode' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['content_type']).to eq('text/plain')
            expect(json['bytes']).to eq(47)
          end
        end
      end

      context "An HTML document with <html><body><h1>Hello, World!</h1></body></html>" do
        let!(:request_input) { StringIO.new "data:text/html,%3Chtml%3E%3Cbody%3E%3Ch1%3EHello,%20World!%3C/h1%3E%3C/body%3E%3C/html%3E" }

        it 'should decode' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['content_type']).to eq('text/plain')
            expect(json['bytes']).to eq(89)
          end
        end
      end

      context "An HTML document that executes a JavaScript alert" do
        let!(:request_input) { StringIO.new "data:text/html,<script>alert('hi');</script>" }

        it 'should decode' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['content_type']).to eq('text/html')
            expect(json['bytes']).to eq(44)
          end
        end
      end
    end

    context 'plain text with data: prefix' do
      let!(:file) { StringIO.new(IO.binread("spec/fixtures/sample.txt"), 'rb') }

      it 'should not be mangled by Base64 decoding' do
        code, headers, body = subject.call
        expect(code).to eq(200)
        expect(headers['Content-Type']).to eq('text/json')
        JSON.parse(body.join('')).tap do |json|
          expect(json).to be_has_key('path')
          expect(json['content_type']).to eq('text/plain')
          expect(json['bytes']).to eq(20)
        end
      end
    end

    context 'save fail locally' do
      before do
        allow(Attache.cache).to receive(:write).and_return(0)
      end

      it 'should respond with error' do
        code, headers, body = subject.call
        expect(code).to eq(500)
        expect(headers['X-Exception']).to eq('Local file failed')
      end
    end

    context 'storage not configured' do
      before do
        allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(nil)
        allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(nil)
      end

      it 'should NOT save file remotely' do
        expect_any_instance_of(Attache::VHost).not_to receive(:storage_create)
        subject.call
      end
    end

    context 'storage configured' do
      before do
        allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(double(:storage))
        allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(double(:bucket))
      end

      it 'should save file remotely' do
        expect_any_instance_of(Attache::VHost).to receive(:storage_create).and_return(anything)
        subject.call
      end
    end

    context 'with secret_key' do
      let(:secret_key) { "topsecret#{rand}" }

      before do
        allow_any_instance_of(Attache::VHost).to receive(:secret_key).and_return(secret_key)
      end

      it 'should respond with error' do
        code, headers, body = subject.call
        expect(code).to eq(401)
        expect(headers['X-Exception']).to eq('Authorization failed')
      end

      context 'invalid auth' do
        let(:expiration) { (Time.now + 10).to_i }
        let(:uuid) { "hi#{rand}" }
        let(:digest) { OpenSSL::Digest.new('sha1') }
        let(:params) { Hash(file: filename, expiration: expiration, uuid: uuid, hmac: OpenSSL::HMAC.hexdigest(digest, "wrong#{secret_key}", "#{uuid}#{expiration}")) }

        it 'should respond with error' do
          code, headers, body = subject.call
          expect(code).to eq(401)
          expect(headers['X-Exception']).to eq('Authorization failed')
        end
      end

      context 'valid auth' do
        let(:expiration) { (Time.now + 10).to_i }
        let(:uuid) { "hi#{rand}" }
        let(:digest) { OpenSSL::Digest.new('sha1') }
        let(:params) { Hash(file: filename, expiration: expiration, uuid: uuid, hmac: OpenSSL::HMAC.hexdigest(digest, secret_key, "#{uuid}#{expiration}")) }

        it 'should respond with success' do
          code, headers, body = subject.call
          expect(code).to eq(200)
        end

        it 'should respond successfully with json with signature' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            json_without_signature = json.reject {|k,v| k == 'signature' }
            generated_signature = OpenSSL::HMAC.hexdigest(digest, secret_key, json_without_signature.sort.collect {|k,v| "#{k}=#{v}" }.join('&'))
            expect(json['signature']).to eq(generated_signature)
          end
        end

        context 'expired' do
          let(:expiration) { (Time.now - 1).to_i } # the past

          it 'should respond with error' do
            code, headers, body = subject.call
            expect(code).to eq(401)
            expect(headers['X-Exception']).to eq('Authorization failed')
          end
        end
      end
    end
  end
end
