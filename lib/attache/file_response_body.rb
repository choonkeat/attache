class Attache::FileResponseBody
  def initialize(file, range_start = nil, range_end = nil)
    @file        = file
    @range_start = range_start || 0
    @range_end   = range_end || File.size(@file.path)
  end

  # adapted from rack/file.rb
  def each
    @file.seek(@range_start)
    remaining_len = @range_end
    while remaining_len > 0
      part = @file.read([8192, remaining_len].min)
      break unless part
      remaining_len -= part.length

      yield part
    end
  end
end
