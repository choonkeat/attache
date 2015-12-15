require 'spec_helper'

describe Attache::Delete do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Delete.new(app) }
  let(:params) { {} }
  let(:filename) { "hello#{rand}.gif" }
  let(:reldirname) { "path#{rand}" }
  let(:file) { StringIO.new(IO.binread("spec/fixtures/transparent.gif"), 'rb') }

  before do
    allow(Attache).to receive(:logger).and_return(Logger.new('/dev/null'))
    allow(Attache).to receive(:localdir).and_return(Dir.tmpdir) # forced, for safety
  end

  after do
    FileUtils.rm_rf(Attache.localdir)
  end

  it "should passthrough irrelevant request" do
    code, env = middleware.call Rack::MockRequest.env_for('http://example.com', {})
    expect(code).to eq 200
  end

  context "deleting" do
    let(:params) { Hash(paths: ['image1.jpg', filename].join("\n")) }

    subject { proc { middleware.call Rack::MockRequest.env_for('http://example.com/delete?' + params.collect {|k,v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}"}.join('&'), method: 'DELETE', "HTTP_HOST" => "example.com") } }

    it 'should respond with json' do
    end

    it 'should delete file locally' do
      expect(Attache.cache).to receive(:delete) do |path|
        expect(path).to start_with('example.com')
      end.exactly(2).times
      code, headers, body = subject.call
      expect(code).to eq(200)
    end

    context 'delete fail locally' do
      before do
        expect(Attache.cache).to receive(:delete) do
          raise Exception.new
        end
      end

      it 'should respond with error' do
        code, headers, body = subject.call
        expect(code).to eq(500)
      end
    end

    context 'storage configured' do
      before do
        allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(double(:storage))
        allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(double(:bucket))
      end

      it 'should delete file remotely' do
        expect_any_instance_of(Attache::VHost).to receive(:async) do |instance, method, path|
          expect(method).to eq(:storage_destroy)
        end.exactly(2).times
        subject.call
      end
    end

    context 'storage NOT configured' do
      it 'should NOT delete file remotely' do
        expect_any_instance_of(Attache::VHost).not_to receive(:async)
        subject.call
      end
    end

    context 'backup configured' do
      let(:backup) { double(:backup) }

      before do
        allow_any_instance_of(Attache::VHost).to receive(:backup).and_return(backup)
      end

      it 'should delete file in backup' do
        expect(backup).to receive(:async) do |method, path|
          expect(method).to eq(:storage_destroy)
        end.exactly(2).times
        subject.call
      end
    end

    context 'backup NOT configured' do
      it 'should NOT delete file in backup' do
        expect_any_instance_of(Attache::VHost).not_to receive(:async)
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
