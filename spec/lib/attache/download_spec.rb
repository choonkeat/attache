require 'spec_helper'

describe Attache::Download do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Download.new(app) }
  let(:params) { {} }
  let(:filename) { "hello#{rand}.gif" }
  let(:reldirname) { "path#{rand}" }
  let(:geometry) { CGI.escape('2x2#') }
  let(:file) { StringIO.new(IO.binread("spec/fixtures/transparent.gif"), 'rb') }

  before do
    allow(Attache).to receive(:logger).and_return(Logger.new('/dev/null'))
    allow(Attache).to receive(:localdir).and_return(Dir.tmpdir) # forced, for safety
  end

  after do
    FileUtils.rm_rf(Attache.localdir)
  end

  it "should passthrough irrelevant request" do
    code, env = middleware.call Rack::MockRequest.env_for('http://example.com', "HTTP_HOST" => "example.com")
    expect(code).to eq 200
  end

  context 'downloading' do
    subject { proc { middleware.call Rack::MockRequest.env_for("http://example.com/view/#{reldirname}/#{geometry}/#{filename}", "HTTP_HOST" => "example.com") } }

    context 'not in local cache' do
      context 'not available remotely' do
        it 'should respond not found' do
          code, headers, body = subject.call
          expect(code).to eq(404)
        end
      end

      context 'available remotely' do
        before do
          allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(double(:storage))
          allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(double(:bucket))
          allow_any_instance_of(Attache::VHost).to receive(:storage_get).and_return(file)
        end

        it 'should proceed normally' do
          code, headers, body = subject.call
          expect(code).to eq(200)
        end
      end
    end

    context 'in local cache' do
      before do
        Attache.cache.write("example.com/#{reldirname}/#{filename}", file)
      end

      it 'should send thumbnail' do
        expect_any_instance_of(middleware.class).to receive(:make_thumbnail_for) do
          Tempfile.new('download').tap do |t|
            t.binmode
            t.write IO.binread("spec/fixtures/transparent.gif")
          end.tap(&:open)
        end
        code, headers, body = subject.call
        expect(code).to eq(200)
        expect(headers['Content-Type']).to eq('image/gif')
      end

      context 'geometry is "original"' do
        let(:geometry) { CGI.escape('original') }

        it 'should send original file' do
          expect_any_instance_of(middleware.class).not_to receive(:make_thumbnail_for)
          code, headers, body = subject.call
          response_content = ''
          body.each {|p| response_content += p }
          original_content = file.tap(&:rewind).read
          expect(response_content).to eq(original_content)
        end
      end
    end
  end
end
