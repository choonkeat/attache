require 'spec_helper'

describe Attache::Delete do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Delete.new(app) }
  let(:storage_api) { double(:storage_api) }
  let(:localdir) { Dir.mktmpdir }

  before do
    allow(Attache).to receive(:localdir).and_return(localdir)
    allow(Attache.cache).to receive(:delete).and_return(true)
    allow(Attache::Storage).to receive(:api).and_return(storage_api)
  end

  it "should passthrough irrelevant request" do
    code, env = middleware.call Rack::MockRequest.env_for('http://example.com', {})
    expect(code).to eq 200
  end

  context "deleting" do
    let(:params) { Hash(paths: ['image1.jpg', 'image2.jpg'].join("\n")) }
    subject { proc { middleware.call Rack::MockRequest.env_for('http://example.com/delete?' + params.collect {|k,v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}"}.join('&'), method: 'DELETE') } }

    it 'should respond with json' do
      code, env, body = subject.call
      expect(env).to be_has_key('Access-Control-Allow-Origin')
      expect(env['Content-Type']).to eq('text/json')
    end

    it 'should delete file locally' do
      expect(Attache.cache).to receive(:delete).and_return(1)
      code, env, body = subject.call
    end

    context 'delete fail locally' do
      before { allow(Attache.cache).to receive(:delete).and_return(0) }

      it 'should respond with error' do
        code, env, body = subject.call
        expect(code).to eq(200)
      end
    end

    context 'storage configured' do
      let(:remote_file) { double(:remote_file) }
      before do
        allow(Attache).to receive(:storage).and_return(double(:storage))
        allow(Attache).to receive(:bucket).and_return("bucket")
        expect(remote_file).to receive(:destroy).twice
      end

      it 'should delete file remotely' do
        expect(storage_api).to receive(:new) do |options|
          expect(['image1.jpg','image2.jpg']).to include(options[:key])
        end.twice.and_return(remote_file)
        subject.call
      end

      context 'remotedir=nil' do
        before { allow(Attache).to receive(:remotedir).and_return(nil) }

        it 'should remote file {relpath}/{filename}' do
          expect(storage_api).to receive(:new) do |options|
            expect(['image1.jpg','image2.jpg']).to include(options[:key])
          end.twice.and_return(remote_file)
          subject.call
        end
      end
    end

    context 'storage NOT configured' do
      before { allow(Attache).to receive(:bucket).and_return(nil) }

      it 'should delete file remotely' do
        expect(storage_api).not_to receive(:create)
        subject.call
      end
    end

    context 'with secret_key' do
      let(:secret_key) { "topsecret" }
      let(:expiration) { (Time.now + 10).to_i }
      before { allow(Attache).to receive(:secret_key).and_return(secret_key) }

      it 'should respond with error' do
        code, env, body = subject.call
        expect(code).to eq(401)
      end

      context 'invalid auth' do
        let(:uuid) { "hi#{rand}" }
        let(:digest) { OpenSSL::Digest.new('sha1') }
        let(:params) { Hash(paths: ['image1.jpg', 'image2.jpg'].join("\n"), expiration: expiration, uuid: uuid, hmac: OpenSSL::HMAC.hexdigest(digest, "wrong#{secret_key}", "#{uuid}#{expiration}")) }

        it 'should respond with error' do
          code, env, body = subject.call
          expect(code).to eq(401)
        end
      end

      context 'valid auth' do
        let(:uuid) { "hi#{rand}" }
        let(:digest) { OpenSSL::Digest.new('sha1') }
        let(:params) { Hash(paths: ['image1.jpg', 'image2.jpg'].join("\n"), expiration: expiration, uuid: uuid, hmac: OpenSSL::HMAC.hexdigest(digest, secret_key, "#{uuid}#{expiration}")) }

        it 'should respond with success' do
          code, env, body = subject.call
          expect(code).to eq(200)
        end

        context 'expired' do
          let(:expiration) { (Time.now - 1).to_i }

          it 'should respond with error' do
            code, env, body = subject.call
            expect(code).to eq(401)
          end
        end
      end
    end
  end

end
