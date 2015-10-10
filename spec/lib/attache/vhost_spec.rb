require 'spec_helper'

describe Attache::VHost do
  let(:config) { { 'HOSTNAME' => 'example.com', 'REMOTE_DIR' => remotedir } }
  let(:vhost) { Attache::VHost.new(config) }
  let(:remote_api) { double(:remote_api) }
  let(:file_io) { StringIO.new("") }
  let(:relpath) { 'relpath' }
  let(:cachekey) { 'hostname/relpath' }
  let(:remotedir) { 'remote_directory' }

  before do
    allow(vhost).to receive(:remote_api).and_return(remote_api)
  end

  describe '#storage_create' do
    it 'should read with cachekey, write with remotedir prefix' do
      expect(Attache.cache).to receive(:read).with(cachekey).and_return(file_io)
      expect(remote_api).to receive(:create).with(key: "#{remotedir}/#{relpath}", body: file_io)
      expect(Attache.outbox).to receive(:delete).with(config['HOSTNAME'], 'relpath')

      vhost.storage_create(relpath: relpath, cachekey: cachekey)
    end

    it 'should ignore source file no longer exist (Errno::ENOENT) and continue deleting outbox' do
      allow(Attache.cache).to receive(:read) { raise Errno::ENOENT }
      expect(remote_api).not_to receive(:create)
      expect(Attache.outbox).to receive(:delete).with(config['HOSTNAME'], 'relpath')

      expect { vhost.storage_create(relpath: relpath, cachekey: cachekey) }.not_to raise_error
    end

    it 'should raise on other errors' do
      allow(Attache.cache).to receive(:read) { raise Exception.new("Other") }
      expect(remote_api).not_to receive(:create)
      expect(Attache.outbox).not_to receive(:delete)

      expect { vhost.storage_create(relpath: relpath, cachekey: cachekey) }.to raise_error
    end
  end
end
