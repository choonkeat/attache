require 'spec_helper'

describe Attache::UploadUrl do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:uploader) { Attache::Upload.new(app) }
  let(:middleware) { Attache::UploadUrl.new(uploader) }
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

  context 'upload as url' do
    subject { proc { middleware.call Rack::MockRequest.env_for('http://' + hostname + '/upload_url?' + params.collect {|k,v| "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}"}.join('&'), method: 'PUT', "HTTP_HOST" => hostname) } }

    context 'to image' do
      let(:params) { Hash(url: "https://raw.githubusercontent.com/choonkeat/attache/master/spec/fixtures/landscape.jpg") }

      it 'should respond successfully with json' do
        code, headers, body = subject.call
        expect(code).to eq(200)
        expect(headers['Content-Type']).to eq('text/json')
        JSON.parse(body.join('')).tap do |json|
          expect(json).to be_has_key('path')
          expect(json['geometry']).to eq('4x3')
        end
      end
    end

    context 'follow redirect; works with non image too' do
      let(:params) { Hash(url: "http://google.com") }

      it 'should respond successfully with json' do
        code, headers, body = subject.call
        expect(code).to eq(200)
        expect(headers['Content-Type']).to eq('text/json')
        JSON.parse(body.join('')).tap do |json|
          expect(json).to be_has_key('path')
          expect(json['path']).not_to end_with('/')
          expect(json['content_type']).to eq('text/html')
        end
      end
    end

    context 'data uri' do
      context 'base64-encoded image' do
        let(:file) { StringIO.new(IO.binread("spec/fixtures/landscape.jpg"), 'rb') }
        let(:params) { Hash(url: "data:image/gif;base64," + Base64.encode64(file.read)) }

        it 'should respond identically as when uploading binary' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['geometry']).to eq('4x3')
            expect(json['bytes']).to eq(425)
          end
        end
      end

      # various Data URI permutations
      # https://developer.mozilla.org/en-US/docs/Web/HTTP/data_URIs
      context 'simple text/plain data' do
        let(:params) { Hash(url: "data:,Hello%2C%20World!") }

        it 'should decode' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['content_type']).to eq('text/plain')
            expect(json['bytes']).to eq(13)
          end
        end
      end

      context "base64-encoded version of the above" do
        let(:params) { Hash(url: "data:text/plain;base64,SGVsbG8sIFdvcmxkIQ%3D%3D") }

        it 'should decode' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['content_type']).to eq('text/plain')
            expect(json['bytes']).to eq(13)
          end
        end
      end

      context "An HTML document with <html><body><h1>Hello, World!</h1></body></html>" do
        let(:params) { Hash(url: "data:text/html,%3Chtml%3E%3Cbody%3E%3Ch1%3EHello,%20World!%3C/h1%3E%3C/body%3E%3C/html%3E") }

        it 'should decode' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['content_type']).to eq('text/html')
            expect(json['bytes']).to eq(48)
          end
        end
      end

      context "An HTML document that executes a JavaScript alert" do
        let(:params) { Hash(url: "data:text/html,<script>alert('hi');</script>") }

        it 'should decode' do
          code, headers, body = subject.call
          expect(code).to eq(200)
          expect(headers['Content-Type']).to eq('text/json')
          JSON.parse(body.join('')).tap do |json|
            expect(json).to be_has_key('path')
            expect(json['content_type']).to eq('text/html')
            expect(json['bytes']).to eq(29)
          end
        end
      end
    end
  end
end
