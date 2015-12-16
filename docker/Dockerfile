FROM ruby:2.2

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y imagemagick

RUN useradd -d /app -m app
RUN chown -R app /usr/local/bundle
USER app

RUN gem install --no-ri --no-rdoc attache --version '>= 1.1.0'
RUN mkdir -p /app/src
WORKDIR /app/src
RUN echo 'gem "attache"' > Gemfile && bundle

EXPOSE 5000
CMD ["attache", "start", "-c", "web=1"]
