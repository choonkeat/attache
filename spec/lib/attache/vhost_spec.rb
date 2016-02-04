require 'spec_helper'

describe Attache::VHost do
  let(:config) { { 'REMOTE_DIR' => remotedir } }
  let(:config_with_backup) { YAML.load_file('config/vhost.example.yml').fetch("aws.example.com").merge('REMOTE_DIR' => remotedir) }
  let(:vhost) { Attache::VHost.new(config) }
  let(:remote_api) { double(:remote_api) }
  let(:file_io) { StringIO.new("") }
  let(:relpath) { 'relpath' }
  let(:cachekey) { 'hostname/relpath' }
  let(:remotedir) { 'remote_directory' }

  before do
    allow(vhost).to receive(:remote_api).and_return(remote_api)
  end

  describe '#storage_url' do
    let(:url) { 'http://example.com/a/b/c' }

    before do
      allow(remote_api).to receive(:new).and_return(files)
      allow_any_instance_of(Fog::Storage::Local::File).to receive(:public_url).and_return(url)
      allow_any_instance_of(Fog::Storage::AWS::File).to receive(:url).and_return(url)
    end

    context 'fog local storage' do
      let(:files) { return Fog::Storage::Local::File.new }

      it 'should return' do
        expect(vhost.storage_url(relpath: relpath)).to eq(url)
      end
    end

    context 'fog s3 storage' do
      let(:files) { return Fog::Storage::AWS::File.new }

      it 'should return' do
        expect(vhost.storage_url(relpath: relpath)).to eq(url)
      end
    end
  end

  describe '#storage_create' do
    it 'should read with cachekey, write with remotedir prefix' do
      expect(Attache.cache).to receive(:read).with(cachekey).and_return(file_io)
      expect(remote_api).to receive(:create).with(key: "#{remotedir}/#{relpath}", body: file_io)
      vhost.storage_create(relpath: relpath, cachekey: cachekey)
    end

    it 'should raise on other errors' do
      allow(Attache.cache).to receive(:read) { raise Exception.new }
      expect(remote_api).not_to receive(:create)

      expect { vhost.storage_create(relpath: relpath, cachekey: cachekey) }.to raise_error(Exception)
    end
  end

  describe '#storage' do
    it { expect(vhost.storage).to be_nil }

    context 'configured' do
      let(:config) { config_with_backup }

      it { expect(vhost.storage).to be_kind_of(Fog::Storage::AWS::Real) }
      it { expect(vhost.storage.region).to eq('us-west-1') }
    end
  end

  describe '#bucket' do
    it { expect(vhost.bucket).to be_nil }

    context 'configured' do
      let(:config) { config_with_backup }

      it { expect(vhost.bucket).to eq("CHANGEME") }
    end
  end

  describe '#backup' do
    it { expect(vhost.backup).to be_nil }

    describe '#backup_file' do
      it 'should not do anything' do
        allow_message_expectations_on_nil
        expect(vhost.storage).not_to receive(:copy_object)
        vhost.backup_file(relpath: relpath)
      end
    end

    context 'configured' do
      let(:config) { config_with_backup }

      it { expect(vhost.backup).to be_kind_of(Attache::VHost) }
      it { expect(vhost.backup.storage).to be_kind_of(Fog::Storage::AWS::Real) }
      it { expect(vhost.backup.storage.region).to eq('us-west-1') }
      it { expect(vhost.backup.bucket).to eq("CHANGEME_BAK") }

      describe '#backup_file' do
        it 'should not do anything' do
          expect(vhost.storage).to receive(:copy_object).with(
            vhost.bucket, "#{remotedir}/#{relpath}",
            vhost.backup.bucket, "#{remotedir}/#{relpath}"
          )
          vhost.backup_file(relpath: relpath)
        end
      end
    end
  end
end
