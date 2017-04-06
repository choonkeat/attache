FROM ruby:2.2

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y imagemagick ghostscript
RUN curl -sSL https://raw.githubusercontent.com/choonkeat/attache/master/docker/bundler_geminstaller_install_with_timeout.rb | ruby

RUN useradd -d /app -m app && \
    chown -R app /usr/local/bundle
USER app
RUN mkdir -p /app/src
WORKDIR /app/src

RUN curl -sSL http://johnvansickle.com/ffmpeg/releases/ffmpeg-release-32bit-static.tar.xz | tar -xJv
ENV PATH "$PATH:/app/src/ffmpeg-2.8.3-32bit-static"

RUN echo 'source "https://rubygems.org"' > Gemfile && \
    echo 'gem "attache", ">= 2.3.0"'     >> Gemfile && bundle && \
    gem install --no-ri --no-rdoc attache --version '>= 2.3.0'

EXPOSE 5000
CMD ["attache", "start", "-c", "web=1"]
