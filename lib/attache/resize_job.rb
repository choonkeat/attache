require 'digest/sha1'
require 'stringio'
require 'mini_magick'

class Attache::ResizeJob
  def perform(instructions, basename, t = Time.now)
    closed_file = yield
    return StringIO.new if closed_file.try(:size).to_i == 0

    Attache.logger.info "[POOL] start"
    transform_image(closed_file, instructions)
  rescue MiniMagick::Invalid
    make_nonimage_preview(closed_file, basename)
  ensure
    Attache.logger.info "[POOL] done in #{Time.now - t}s"
  end

  private

    BOLD_FONT_FILE = ENV.fetch('FONT_FILE', File.join(Attache.publicdir, "vendor/roboto/Roboto-Medium.ttf"))
    THIN_FONT_FILE = ENV.fetch('FONT_FILE', File.join(Attache.publicdir, "vendor/roboto/Roboto-Light.ttf"))
    BORDER_SIZE = ENV.fetch('BORDER_SIZE', "3")
    FG_COLOR = ENV.fetch('FG_COLOR', "#ffffff")
    BG_COLOR = ENV.fetch('BG_COLOR', "#dddddd")
    EXT_COLOR = ENV.fetch('EXT_COLOR', "#333333")
    TXT_SIZE = ENV.fetch('TXT_SIZE', "12")
    PREVIEW_SIZE = ENV.fetch('PREVIEW_SIZE', '96x')

    def make_nonimage_preview(closed_file, basename)
      t = Time.now
      Attache.logger.info "[POOL] start nonimage preview"
      output_file = Tempfile.new(["preview", ".png"]).tap(&:close)
      cmd = case basename
      when /\.pdf$/i
        "convert -size #{PREVIEW_SIZE.inspect} #{closed_file.path.inspect}[0] -thumbnail #{PREVIEW_SIZE.inspect} -font #{BOLD_FONT_FILE.inspect}"
      else
        "convert -size #{PREVIEW_SIZE.inspect} \\( -gravity center -font #{BOLD_FONT_FILE.inspect} -fill #{EXT_COLOR.inspect} label:'#{make_safe_filename(basename).split(/\W+/).last}' \\)"
      end + " -bordercolor #{FG_COLOR.inspect} -border #{BORDER_SIZE} -background #{BG_COLOR.inspect} -gravity center -font #{THIN_FONT_FILE.inspect} -pointsize 12 -set caption #{basename.inspect} -polaroid 0 #{output_file.path.inspect}"
      Attache.logger.info cmd
      system cmd
      File.new(output_file.path)
    ensure
      Attache.logger.info "[POOL] done nonimage preview in #{Time.now - t}s"
    end

    def make_safe_filename(str)
      str.to_s.gsub(/[^\w\.]/, '_')
    end

    def transform_image(closed_file, instructions, max: 2048)
      image = MiniMagick::Image.open(closed_file.path)

      image.combine_options do |b|
        instructions.each do |instruction|
          b.public_send(instruction[0], *instruction[1..-1])
        end
      end

      # Keep tempfile open for the consumer of this class to work with
      image.tempfile.open
    end
end
