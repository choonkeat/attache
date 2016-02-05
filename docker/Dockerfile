FROM ruby:2.2

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y imagemagick ghostscript

RUN useradd -d /app -m app
RUN chown -R app /usr/local/bundle
USER app

RUN gem install --no-ri --no-rdoc attache --version '>= 2.1.1'
RUN mkdir -p /app/src
WORKDIR /app/src
RUN echo 'gem "attache"' > Gemfile && bundle

RUN wget http://johnvansickle.com/ffmpeg/releases/ffmpeg-release-32bit-static.tar.xz
RUN tar xvf ffmpeg-release-32bit-static.tar.xz
ENV PATH "$PATH:/app/src/ffmpeg-2.8.3-32bit-static"

EXPOSE 5000
CMD ["attache", "start", "-c", "web=1"]
