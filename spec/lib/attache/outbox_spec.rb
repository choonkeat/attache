require 'spec_helper'

describe Attache::Outbox do
  let(:hostname) { "example.com" }
  let(:relpath)  { File.join(SecureRandom.hex.scan(/../), 'Exãmple#{rand}.gif') }
  let(:src) { "spec/fixtures/transparent.gif" }
  let(:io) { StringIO.new(IO.binread(src), 'rb') }
  let(:destpath) { File.join(Attache::Outbox::OUTBOX_DIR, hostname, relpath) }

  after do
    FileUtils.rm_rf(File.join(Attache::Outbox::OUTBOX_DIR, hostname))
  end

  describe '#write' do
    it "should write file into `OUTBOX_DIR/hostname/relpath`" do
      expect {
        Attache.outbox.write(hostname, relpath, io)
      }.to change { File.exists?(destpath) }.to eq(true)
      expect(FileUtils.identical?(src, destpath)).to eq(true)
    end
  end

  describe '#delete' do
    before do
      Attache.outbox.write(hostname, relpath, io)
    end

    it "should remove file from `OUTBOX_DIR/hostname/relpath`" do
      expect {
        Attache.outbox.delete(hostname, relpath)
      }.to change { File.exists?(destpath) }.to eq(false)
      expect(File.exists?(File.dirname(destpath))).to eq(false)
      expect(File.exists?(File.dirname(File.dirname destpath))).to eq(false)
    end
  end
end
