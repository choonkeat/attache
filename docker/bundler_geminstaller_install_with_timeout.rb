# Usage:
#   ruby bundler_geminstaller_install_with_timeout.rb

target = `which bundle`.chomp
*old_lines, last_line = IO.read(target).split(/[\r\n]+/)
if (old_lines.grep(/install_with_timeout/)).empty?
  new_line = IO.read(__FILE__).split('__END__').last.strip
  combined = (old_lines + [new_line, last_line]).join($/)
  open(target, "w") {|f| f.write(combined) }
  puts "installed."
else
  puts "already installed."
end

__END__

require "timeout"

require "rubygems/installer"
Gem::Installer.class_eval do
  def install_with_timeout
    puts "Gem install_with_timeout..."
    Timeout.timeout(Integer(ENV.fetch("GEM_INSTALL_TIMEOUT", 60))) {
      install_without_timeout
    }
  rescue Timeout::Error
    @tries = @tries.to_i + 1
    raise unless @tries < 5
    STDERR.puts "Gem timed out #{$!} (#{@tries})..."
    retry
  end

  alias :install_without_timeout :install
  alias :install :install_with_timeout
end

require "bundler/installer/gem_installer"
Bundler::GemInstaller.class_eval do
  def install_with_timeout
    puts "Bundler install_with_timeout..."
    Timeout.timeout(Integer(ENV.fetch("GEM_INSTALL_TIMEOUT", 60))) {
      install_without_timeout
    }
  rescue Timeout::Error
    @tries = @tries.to_i + 1
    raise unless @tries < 5
    STDERR.puts "Bundler timed out #{$!} (#{@tries})..."
    retry
  end

  alias :install_without_timeout :install
  alias :install :install_with_timeout
end
