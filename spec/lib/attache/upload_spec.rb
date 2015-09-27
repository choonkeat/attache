require 'spec_helper'

describe Attache::Upload do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Upload.new(app) }
  let(:params) { {} }
  let(:filename) { "Exãmple#{rand}.gif" }
  let(:file) { StringIO.new(IO.binread("spec/fixtures/transparent.gif"), 'rb') }
  let(:hostname) { "example.com" }

  before do
    allow(Attache).to receive(:logger).and_return(Logger.new('/dev/null'))
    allow(Attache).to receive(:localdir).and_return(Dir.tmpdir) # forced, for safety
    allow(Attache.outbox).to receive(:write).and_return(1)
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

    subject { proc { middleware.call Rack::MockRequest.env_for('http://' + hostname + '/upload?' + params.collect {|k,v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}"}.join('&'), method: 'PUT', input: file, "HTTP_HOST" => hostname) } }

    it 'should respond successfully with json' do
      code, headers, body = subject.call
      expect(code).to eq(200)
      expect(headers['Content-Type']).to eq('text/json')
      JSON.parse(body.join('')).tap do |json|
        expect(json).to be_has_key('path')
      end
    end

    it 'should wrote to cache with params[:file] as filename' do
      code, headers, body = subject.call
      json = JSON.parse(body.join(''))
      relpath = json['path']
      expect(relpath).to end_with(params[:file])
      expect(Attache.cache.read(hostname + '/' + relpath).tap(&:close)).to be_kind_of(File)
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
        expect_any_instance_of(Attache::VHost).not_to receive(:async)
        subject.call
      end

      it 'should NOT save file in pending upload' do
        expect(Attache.outbox).not_to receive(:write)
        subject.call
      end
    end

    context 'storage configured' do
      before do
        allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(double(:storage))
        allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(double(:bucket))
        allow_any_instance_of(Attache::VHost).to receive(:storage_create).and_return(nil)
      end

      it 'should save file remotely' do
        expect_any_instance_of(Attache::VHost).to receive(:async).with(:storage_create, any_args)
        subject.call
      end

      it 'should save file in pending upload' do
        expect(Attache.outbox).to receive(:write).with(hostname, *any_args)
        subject.call
      end

      context 'save outbox failed' do
        before do
          allow(Attache.outbox).to receive(:write).and_return(0)
        end

        it 'should respond with error' do
          code, headers, body = subject.call
          expect(code).to eq(500)
          expect(headers['X-Exception']).to eq('Outbox file failed')
        end
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
