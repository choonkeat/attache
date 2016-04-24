FROM ruby:2.2

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y imagemagick ghostscript
RUN wget -O $TMPDIR/bundler_geminstaller_install_with_timeout.rb "https://gist.githubusercontent.com/choonkeat/e7196200db3b24f0898e17dc753171d5/raw/7583a734a5e2569d070461c430fd239be10ad720/bundler_geminstaller_install_with_timeout.rb"
RUN ruby $TMPDIR/bundler_geminstaller_install_with_timeout.rb

RUN useradd -d /app -m app
RUN chown -R app /usr/local/bundle
USER app
RUN mkdir -p /app/src
WORKDIR /app/src

RUN wget http://johnvansickle.com/ffmpeg/releases/ffmpeg-release-32bit-static.tar.xz
RUN tar xvf ffmpeg-release-32bit-static.tar.xz
ENV PATH "$PATH:/app/src/ffmpeg-2.8.3-32bit-static"

RUN echo 'source "https://rubygems.org"' > Gemfile
RUN echo 'gem "attache", ">= 2.3.0"'     >> Gemfile && bundle
RUN gem install --no-ri --no-rdoc attache --version '>= 2.3.0'

EXPOSE 5000
CMD ["attache", "start", "-c", "web=1"]
