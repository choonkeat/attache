require 'spec_helper'

describe Attache::Download do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Download.new(app) }
  let(:storage_api) { double(:storage_api) }
  let(:localdir) { Dir.mktmpdir }
  let(:file) { Tempfile.new("file") }
  let(:thumbnail) { Tempfile.new("thumbnail") }

  before do
    allow(Attache).to receive(:localdir).and_return(localdir)
    allow(Attache.cache).to receive(:write).and_return(1)
    allow(Attache.cache).to receive(:read).and_return(file.tap(&:open))
    allow(middleware).to receive(:content_type_of).and_return('image/gif')
    allow(middleware).to receive(:make_thumbnail_for) {|file, geometry, extension| thumbnail.tap(&:open)}
    allow(middleware).to receive(:rack_response_body_for).and_return([])
    allow(Attache::Storage).to receive(:api).and_return(storage_api)
  end

  after do
    FileUtils.rm_r(Dir[File.join(localdir, '*')])
  end

  it "should passthrough irrelevant request" do
    code, env = middleware.call Rack::MockRequest.env_for('http://example.com', {})
    expect(code).to eq 200
  end

  describe '#parse_path_info' do
    it "should work" do
      middleware.send(:parse_path_info, "one/two/three/10x20%23/file%20extension.jpg") do |dirname, geometry, basename, relpath|
        expect(dirname).to  eq "one/two/three"
        expect(geometry).to eq "10x20#"
        expect(basename).to eq "file extension.jpg"
        expect(relpath).to eq File.join("one/two/three/file extension.jpg")
      end
    end

    context "with GEOMETRY_ALIAS" do
      before { allow(Attache).to receive(:geometry_alias).and_return("small" => "64x64#", "large" => "128x128>") }

      it "should apply Attache.geometry_alias" do
        middleware.send(:parse_path_info, "one/two/three/small/file%20extension.jpg") do |dirname, geometry, basename, relpath|
          expect(geometry).to eq "64x64#"
        end
        middleware.send(:parse_path_info, "one/two/three/large/file%20extension.jpg") do |dirname, geometry, basename, relpath|
          expect(geometry).to eq "128x128>"
        end
      end
      it "should use value as-is when lookup fail" do
        middleware.send(:parse_path_info, "one/two/three/notfound/file%20extension.jpg") do |dirname, geometry, basename, relpath|
          expect(geometry).to eq "notfound"
        end
      end
    end
  end

  context 'downloading' do
    let(:uploader) { Attache::Upload.new(app) }
    let(:filename) { "image#{rand}.gif" }
    let(:geometry) { "10x10>" }
    let(:relpath) { File.dirname(uploader.send(:generate_relpath, filename)) }
    let(:fullpath) {
      File.join(localdir, relpath, filename).tap {|p|
        FileUtils.mkdir_p(File.dirname(p))
        open(p, 'wb') {|f| f.write(open('spec/fixtures/transparent.gif', 'rb').read) }
      }
    }
    let(:cached_dst_path) { File.join(Attache.localdir, relpath, middleware.send(:sanitize_geometry_path, geometry), filename) }
    let(:rel_dir)  { File.dirname(fullpath[localdir.length+1..-1]) }
    let(:geometrypath) { "#{rel_dir}/#{CGI.escape(geometry)}/#{filename}" }

    subject { proc { middleware.call Rack::MockRequest.env_for("http://example.com/view/#{geometrypath}", {}) } }

    it 'should send thumbnail' do
      expect(middleware).to receive(:make_thumbnail_for)

      code, env, body = subject.call

      expect(env['X-Exception']).to eq(nil)
    end

    it 'should keep file.open for response' do
      expect(middleware).to receive(:rack_response_body_for) do |file|
        expect(file).not_to be_closed
      end

      code, env, body = subject.call

      expect(env['X-Exception']).to eq(nil)
    end

    it 'should close original file' do
      expect(file).to receive(:close)

      code, env, body = subject.call

      expect(env['X-Exception']).to eq(nil)
    end

    context 'geometry is "original"' do
      let(:geometry) { 'original' }

      it 'should send original file' do
        expect(middleware).not_to receive(:make_thumbnail_for)

        code, env, body = subject.call

        expect(env['X-Exception']).to eq(nil)
      end

      it 'should keep file.open for response' do
        expect(middleware).to receive(:rack_response_body_for) do |file|
          expect(file).not_to be_closed
        end

        code, env, body = subject.call

        expect(env['X-Exception']).to eq(nil)
      end

      it 'should not close original file' do
        expect(file).not_to receive(:close)

        code, env, body = subject.call

        expect(env['X-Exception']).to eq(nil)
      end
    end

    context 'not in local cache' do
      let(:read_results) { [nil, remotefile] }
      before do
        allow(Attache).to receive(:storage).and_return(double(:storage))
        allow(Attache).to receive(:bucket).and_return("bucket")
        allow(Attache.cache).to receive(:read) do
          read_results.shift.tap do |file|
            raise Errno::ENOENT.new unless file
          end
        end
      end

      context 'available remotely' do
        let!(:remotefile) { file }

        it 'should get from storage' do
          expect(storage_api).to receive(:get) do |path|
            expect(path).not_to start_with('/')
            expect(path).to eq(File.join(*Attache.remotedir, relpath, filename))
            double(:remote_object)
          end
          expect(middleware).to receive(:make_thumbnail_for)

          code, env, body = subject.call
          expect(code).to eq(200)
        end
      end

      context 'not available remotely' do
        let!(:remotefile) { nil }

        it 'should get from storage' do
          expect(storage_api).to receive(:get).and_return(nil)
          expect(middleware).not_to receive(:make_thumbnail_for)

          code, env, body = subject.call
          expect(code).to eq(404)
        end
      end
    end
  end
end
