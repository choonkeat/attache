require 'spec_helper'

describe Attache::ResizeJob do
  describe '#thumbnail_for' do
    let(:max) { 2048 }
    let(:current) { [1, 1] }
    let(:current_w) { current.shift }
    let(:current_h) { current.shift }
    let(:job) { Attache::ResizeJob.new }
    let(:original_path) { "spec/fixtures/transparent.gif" }

    before {
      allow(job).to receive(:current_geometry_for).and_return(Paperclip::Geometry.new(current_w, current_h))
      Attache.cache.delete(Digest::SHA1.hexdigest("#{max}x#{max}>" + original_path))
    }

    subject {
      job.send(:thumbnail_for, closed_file: File.new(original_path),
                               target_geometry_string: target,
                               extension: "gif").file.path
    }

    context 'target > max' do
      let(:target) { ["#{max+1}x1>", "1x#{max+1}>"].sample }

      it {
        expect_any_instance_of(Paperclip::Thumbnail).not_to receive(:make)
        is_expected.to eq(original_path)
      }
    end

    context 'target <= max' do
      let(:target) { ["#{max}x1>", "1x#{max}>"].sample }

      context 'current > max' do
        let(:current) { [max+1, 1].shuffle }

        it {
          expect_any_instance_of(Paperclip::Thumbnail).to receive(:make) do |instance|
            expect(instance.target_geometry.to_s).to eq("#{max}x#{max}>")
            File.new(original_path)
          end
          is_expected.not_to eq(original_path)
        }
      end

      context 'current <= max' do
        let(:current) { [max-1, 1].shuffle }

        it {
          expect_any_instance_of(Paperclip::Thumbnail).not_to receive(:make)
          is_expected.to eq(original_path)
        }
      end
    end
  end
end
