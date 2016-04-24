require 'spec_helper'

describe Attache::Backup do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Backup.new(app) }
  let(:params) { {} }
  let(:filename) { "hello#{rand}.gif" }
  let(:reldirname) { "path#{rand}" }
  let(:file) { StringIO.new(IO.binread("spec/fixtures/transparent.gif"), 'rb') }

  before do
    allow(Attache).to receive(:localdir).and_return(Dir.tmpdir) # forced, for safety
    allow_any_instance_of(Attache::VHost).to receive(:secret_key).and_return(nil)
    allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(nil)
    allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(nil)
  end

  after do
    FileUtils.rm_rf(Attache.localdir)
  end

  it "should passthrough irrelevant request" do
    code, env = middleware.call Rack::MockRequest.env_for('http://example.com', {})
    expect(code).to eq 200
  end

  context "backup file" do
    let(:params) { Hash(paths: ['image1.jpg', filename].join("\n")) }

    subject { proc { middleware.call Rack::MockRequest.env_for('http://example.com/backup?' + params.collect {|k,v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}"}.join('&'), method: 'DELETE', "HTTP_HOST" => "example.com") } }

    it 'should respond with json' do
    end

    it 'should not touch local file' do
      expect(Attache).not_to receive(:cache)
      code, headers, body = subject.call
      expect(code).to eq(200)
    end

    context 'storage configured' do
      before do
        allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(double(:storage))
        allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(double(:bucket))
      end

      it 'should backup file' do
        expect_any_instance_of(Attache::VHost).to receive(:backup_file).exactly(2).times
        subject.call
      end
    end

    context 'storage NOT configured' do
      it 'should backup file' do
        expect_any_instance_of(Attache::VHost).not_to receive(:backup_file)
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
