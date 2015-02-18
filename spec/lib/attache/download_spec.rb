require 'spec_helper'

describe Attache::Download do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Download.new(app) }
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

  describe '#parse_path_info' do
    it "should work" do
      middleware.send(:parse_path_info, "one/two/three/10x20%23/file%20extension.jpg") do |dirname, geometry, basename, dst_path|
        expect(dirname).to  eq "one/two/three"
        expect(geometry).to eq "10x20#"
        expect(basename).to eq "file extension.jpg"
        expect(dst_path).to eq File.join(localdir, "one/two/three/10x20-#{Digest::SHA1.hexdigest(geometry)}/file extension.jpg")
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

    it 'should respond with json' do
      code, env, body = subject.call

      expect(env['Content-Type']).to eq('image/gif')
    end

    context 'without cached transformation' do
      before { expect(File.exists?(cached_dst_path)).to be false }

      it 'should generate on the fly' do
        expect(middleware).to receive(:transform_local_file).and_return(fullpath)

        code, env, body = subject.call

        expect(env['Content-Type']).to eq('image/gif')
      end
    end

    context 'cached transformation' do
      before do
        FileUtils.mkdir_p(File.dirname(cached_dst_path))
        FileUtils.cp('README.md', cached_dst_path)
      end

      it 'should use cached file' do
        expect(middleware).not_to receive(:transform_local_file)

        code, env, body = subject.call

        expect(env['Content-Type']).to eq('text/plain')
      end
    end

    context 'without local src' do
      before { File.unlink(fullpath) }

      context 'with storage' do
        before { allow(Attache).to receive(:bucket).and_return("bucket") }

        it 'should retrieve src from storage' do
          expect(storage).to receive(:get_object) do |bucket, path|
            expect(bucket).to eq(Attache.bucket)
            expect(path).to eq(File.join(Attache.remotedir, relpath, filename))
            double(:remote_object, body: "hello")
          end
          expect(middleware).to receive(:transform_local_file).and_return(fullpath)

          code, env, body = subject.call
        end
      end

      context 'without storage' do
        it 'should 404' do
          allow(Attache).to receive(:storage).and_return(nil)

          code, env, body = subject.call

          expect(code).to eq(404)
        end
      end
    end
  end
end
