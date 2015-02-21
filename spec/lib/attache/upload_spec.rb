require 'spec_helper'
require 'stringio'

describe Attache::Upload do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Upload.new(app) }
  let(:storage) { double(:storage) }
  let(:localdir) { Dir.mktmpdir }

  before do
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
    subject { proc { middleware.call Rack::MockRequest.env_for('http://example.com/upload?file=image.jpg', method: 'PUT') } }

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
      code, env, body = subject.call
      JSON.parse(body.join('')).tap do |json|
        expect(File).to be_exist(File.join(localdir, json['path']))
      end
    end

    context 'save fail locally' do
      before { allow(middleware).to receive(:local_save).and_return(false) }

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
  end

end
