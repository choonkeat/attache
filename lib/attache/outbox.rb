class Attache::Outbox
  OUTBOX_DIR = ENV.fetch('OUTBOX_DIR') { 'outbox' }

  def write(hostname, relpath, src)
    destpath = File.join(OUTBOX_DIR, hostname, relpath)
    FileUtils.mkdir_p(File.dirname destpath)
    open(destpath, 'wb') {|dest| IO.copy_stream(src, dest) }
  end

  def delete(hostname, relpath)
    destpath = File.join(OUTBOX_DIR, hostname, relpath)
    File.unlink(destpath)
    Dir.unlink(destpath) while destpath = File.dirname(destpath)
  rescue SystemCallError
    # ignore delete failures
  end
end
