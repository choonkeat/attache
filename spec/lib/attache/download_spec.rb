require 'spec_helper'
require 'base64'
require 'json'

describe Attache::Download do
  let(:app) { ->(env) { [200, env, "app"] } }
  let(:middleware) { Attache::Download.new(app) }
  let(:params) { {} }
  let(:filename) { "hello#{rand}.gif" }
  let(:reldirname) { "path#{rand}" }
  # let(:geometry) { CGI.escape('2x2#') }
  let(:secret_key) { "abc123" }
  let(:instructions) { [["resize", "2x2"]] }
  let(:instruction_string) { Base64.urlsafe_encode64(JSON.generate(instructions), padding: false) }
  let(:hmac) { OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha1"), secret_key, instruction_string) }
  let(:file) { StringIO.new(IO.binread("spec/fixtures/transparent.gif"), 'rb') }
  let(:remote_url) { "http://example.com/image.jpg" }

  before do
    allow(Attache).to receive(:localdir).and_return(Dir.tmpdir) # forced, for safety
    allow_any_instance_of(Attache::VHost).to receive(:secret_key).and_return(secret_key)
  end

  after do
    FileUtils.rm_rf(Attache.localdir)
  end

  it "should passthrough irrelevant request" do
    code, env = middleware.call Rack::MockRequest.env_for('http://example.com', "HTTP_HOST" => "example.com")
    expect(code).to eq 200
  end

  context 'downloading' do
    subject { proc { middleware.call Rack::MockRequest.env_for("http://example.com/view/#{reldirname}/#{instruction_string}/#{hmac}/#{filename}", "HTTP_HOST" => "example.com") } }

    context 'not in local cache' do
      before do
        Attache.cache.delete("example.com/#{reldirname}/#{filename}")
      end

      context 'no cloud storage configured' do
        before do
          allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(nil)
          allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(nil)
        end

        it 'should respond not found' do
          code, headers, body = subject.call
          expect(code).to eq(404)
        end

        it 'should continue to respond not found' do
          code, headers, body = subject.call
          expect(code).to eq(404)
          code, headers, body = subject.call
          expect(code).to eq(404)
        end
      end

      context 'with cloud storage configured' do
        before do
          allow_any_instance_of(Attache::VHost).to receive(:storage).and_return(double(:storage, directories: Struct.new(:key, :files)))
          allow_any_instance_of(Attache::VHost).to receive(:bucket).and_return(double(:bucket))
        end

        it 'should respond not found' do
          code, headers, body = subject.call
          expect(code).to eq(404)
        end

        context 'with backup configured' do
          it 'should respond not found' do
            allow_any_instance_of(Attache::VHost).to receive(:backup).and_return(double(:backup, storage_get: nil))
            code, headers, body = subject.call
            expect(code).to eq(404)
          end

          it 'should respond found if in backup' do
            allow_any_instance_of(Attache::VHost).to receive(:backup).and_return(double(:backup, storage_get: file))
            code, headers, body = subject.call
            expect(code).to eq(200)
          end
        end

        context 'available remotely' do
          before do
            allow_any_instance_of(Attache::VHost).to receive(:storage_get).and_return(file)
            allow_any_instance_of(Attache::VHost).to receive(:storage_url).and_return(remote_url)
          end

          it 'should proceed normally' do
            code, headers, body = subject.call
            expect(code).to eq(200)
          end

          context 'geometry is "remote"' do
            let(:instruction_string) { 'remote' }

            it 'should send remote file' do
              expect(Attache.cache).not_to receive(:fetch)
              expect_any_instance_of(Attache::VHost).to receive(:storage_url)
              code, headers, body = subject.call
              response_content = ''
              body.each {|p| response_content += p }
              expect(response_content).to eq('')
              expect(code).to eq(302)
              expect(headers['Location']).to eq(remote_url)
              expect(headers['Cache-Control']).to eq("private, no-cache")
            end
          end
        end
      end
    end

    context 'in local cache' do
      before do
        Attache.cache.write("example.com/#{reldirname}/#{filename}", file)
      end

      context 'instruction string is "original"' do
        let(:instruction_string) { 'original' }

        it 'should send original file' do
          expect_any_instance_of(middleware.class).not_to receive(:get_thumbnail_file)
          code, headers, body = subject.call
          response_content = ''
          body.each {|p| response_content += p }
          original_content = file.tap(&:rewind).read
          expect(response_content).to eq(original_content)
        end
      end

      context "instruction string contains instructions" do
      end

      # context 'geometry_whitelist is present' do
      #   let(:geometry_whitelist) { ['100x100'] }

      #   before do
      #     allow(middleware).to receive(:vhost_for).and_return(double(:vhost,
      #       geometry_whitelist: geometry_whitelist,
      #       storage: nil,
      #       backup: nil,
      #       download_headers: {}))
      #   end

      #   context 'geometry is whitelisted' do
      #     let(:geometry) { geometry_whitelist.sample }

      #     it 'should be allowed' do
      #       code, headers, body = subject.call
      #       expect(code).to eq(200)
      #     end
      #   end

      #   context 'geometry is NOT whitelisted' do
      #     let(:geometry) { '999x999' }

      #     it 'should NOT be allowed' do
      #       code, headers, body = subject.call
      #       expect(code).to eq(415)
      #       expect(body).to eq(["#{geometry} is not supported"])
      #     end
      #   end
      # end

      context 'rendering' do
        context 'non image' do
          let(:file) { StringIO.new(IO.binread("spec/fixtures/sample.txt"), 'rb') }
          let(:filename) { "hello#{rand}.txt" }

          it 'should output as png' do
            expect_any_instance_of(Attache::ResizeJob).to receive(:make_nonimage_preview).exactly(1).times.and_call_original
            code, headers, body = subject.call
            expect(code).to eq(200)
            expect(headers['Content-Type']).to eq("image/png")
          end
        end

        context 'image' do
          it 'should output as gif' do
            expect_any_instance_of(Attache::ResizeJob).not_to receive(:make_nonimage_preview)
            code, headers, body = subject.call
            expect(code).to eq(200)
            expect(headers['Content-Type']).to eq("image/gif")
          end
        end
      end
    end
  end
end
