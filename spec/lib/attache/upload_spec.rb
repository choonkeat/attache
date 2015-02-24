require 'spec_helper'
require 'stringio'

describe Attache::Upload do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Upload.new(app) }
  let(:storage) { double(:storage) }
  let(:localdir) { Dir.mktmpdir }
  let(:file) { double(:file, closed?: true, path: localdir + "/image.jpg") }

  before do
    allow(middleware).to receive(:content_type_of).and_return('image/jpeg')
    allow(middleware).to receive(:geometry_of).and_return('100x100')
    allow(Attache.cache).to receive(:write).and_return(1)
    allow(Attache.cache).to receive(:read).and_return(file)
    allow(Attache).to receive(:storage).and_return(storage)
    allow(Attache).to receive(:localdir).and_return(localdir)
    allow(storage).to receive(:put_object)
  end

  after do
    FileUtils.rm_r(Dir[File.join(localdir, '*')])
  end

  it "should passthrough irrelevant request" do
    code, env = middleware.call Rack::MockRequest.env_for('http://example.com', {})
    expect(code).to eq 200
  end

  context "uploading" do
    let(:params) { Hash(file: 'image.jpg') }
    subject { proc { middleware.call Rack::MockRequest.env_for('http://example.com/upload?' + params.collect {|k,v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}"}.join('&'), method: 'PUT') } }

    it 'should respond with json' do
      code, env, body = subject.call
      expect(env).to be_has_key('Access-Control-Allow-Origin')
      expect(env['Content-Type']).to eq('text/json')

      JSON.parse(body.join('')).tap do |json|
        expect(json).to be_has_key('content_type')
        expect(json).to be_has_key('geometry')
        expect(json).to be_has_key('path')

        expect(json['path']).to match(%r{\A\w\w/})
      end
    end

    it 'should save file locally' do
      expect(Attache.cache).to receive(:write).and_return(1)
      code, env, body = subject.call
    end

    context 'save fail locally' do
      before { allow(Attache.cache).to receive(:write).and_return(0) }

      it 'should respond with error' do
        code, env, body = subject.call
        expect(code).to eq(500)
      end
    end

    context 'storage configured' do
      before { allow(Attache).to receive(:bucket).and_return("bucket") }

      it 'should save file remotely' do
        expect(storage).to receive(:put_object) do |bucket, path, io|
          expect(bucket).to eq(Attache.bucket)
          expect(path).not_to start_with('/')
        end
        subject.call
      end

      context 'remotedir=nil' do
        before { allow(Attache).to receive(:remotedir).and_return(nil) }

        it 'should remote file {relpath}/{filename}' do
          expect(storage).to receive(:put_object) do |bucket, path, io|
            expect(path).not_to start_with('/')
          end
          subject.call
        end
      end
    end

    context 'storage NOT configured' do
      before { allow(Attache).to receive(:bucket).and_return(nil) }

      it 'should save file remotely' do
        expect(storage).not_to receive(:put_object)
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
        let(:params) { Hash(file: 'image.jpg', expiration: expiration, uuid: uuid, hmac: OpenSSL::HMAC.hexdigest(digest, "wrong#{secret_key}", "#{uuid}#{expiration}")) }

        it 'should respond with error' do
          code, env, body = subject.call
          expect(code).to eq(401)
        end
      end

      context 'valid auth' do
        let(:uuid) { "hi#{rand}" }
        let(:digest) { OpenSSL::Digest.new('sha1') }
        let(:params) { Hash(file: 'image.jpg', expiration: expiration, uuid: uuid, hmac: OpenSSL::HMAC.hexdigest(digest, secret_key, "#{uuid}#{expiration}")) }

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
