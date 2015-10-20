require 'spec_helper'

describe Attache::Tus do
  let(:env) { @env }
  let(:config) { @config }
  let(:tus) { Attache::Tus.new(env, config) }

  it "should return Entity-Length for upload_length" do
    @env = { 'HTTP_ENTITY_LENGTH' => rand }
    expect(tus.upload_length).to eq(@env['HTTP_ENTITY_LENGTH'])
  end

  it "should prefer Upload-Length for upload_length" do
    @env = { 'HTTP_ENTITY_LENGTH' => rand, 'HTTP_UPLOAD_LENGTH' => rand }
    expect(tus.upload_length).to eq(@env['HTTP_UPLOAD_LENGTH'])
  end

  it "should return Offset for upload_offset" do
    @env = { 'HTTP_OFFSET' => rand }
    expect(tus.upload_offset).to eq(@env['HTTP_OFFSET'])
  end

  it "should prefer Upload-Offset for upload_offset" do
    @env = { 'HTTP_OFFSET' => rand, 'HTTP_UPLOAD_OFFSET' => rand }
    expect(tus.upload_offset).to eq(@env['HTTP_UPLOAD_OFFSET'])
  end

  it "should parse upload_metadata" do
    @env = { "HTTP_UPLOAD_METADATA" => "key dmFsdWU=,randkey0.87393016369783 cmFuZHZhbHVlMC44MzYxNjcyOTk3OTQyMTU2" }
    expect(tus.upload_metadata).to eq({
      "key" => "value",
      "randkey0.87393016369783" => "randvalue0.8361672997942156",
    })
  end
end
