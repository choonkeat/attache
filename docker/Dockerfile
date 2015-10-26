FROM ruby:2.2

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y imagemagick
RUN gem install attache --version '>= 1.0.2'

RUN useradd -d /app -m app
USER app
RUN mkdir -p /app/src
WORKDIR /app/src
RUN echo 'gem "attache"' > Gemfile && bundle

EXPOSE 5000
CMD ["/usr/local/bundle/bin/attache", "start", "-c", "web=1"]
