require 'spec_helper'

describe Attache::UploadUrl do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:uploader) { Attache::Upload.new(app) }
  let(:middleware) { Attache::UploadUrl.new(uploader) }
  let(:hostname) { "example.com" }

  before do
    allow(Attache).to receive(:logger).and_return(Logger.new('/dev/null'))
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
  end
end
