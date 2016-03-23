# attache

[![Gem Version](https://badge.fury.io/rb/attache.svg)](https://badge.fury.io/rb/attache)
[![Build Status](https://travis-ci.org/choonkeat/attache.svg?branch=master)](https://travis-ci.org/choonkeat/attache)

## But why?

If you're interested in the "why", checkout [my slides](http://www.slideshare.net/choonkeat/file-upload-2015) and [the blog post](http://blog.choonkeat.com/weblog/2015/10/file-uploads-2015.html).

Your app can easily support
- dynamic resize of images (no predefined styles in your app)
- all file types since attache let apps [display non-image files as icons through `<img src...>`](https://github.com/choonkeat/attache/pull/28)
- resumeable upload over unreliable (mobile) networks [using TUS protocol](https://github.com/choonkeat/attache/pull/10)

## Run an instance

#### Heroku

You can run your own instance on your own Heroku server

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy)

#### Docker

```
docker run -it -p 9292:5000 --rm attache/attache
```

Also, see [Deploying Attache on Digital Ocean using Docker](https://github.com/choonkeat/attache/wiki/Deploying-Attache-on-Digital-Ocean-using-Docker)

#### RubyGem

You can install the gem and then execute `attache` command

```
gem install attache
attache start -c web=1 -p 9292
```

NOTE: some config files will be written into your current directory

```
.
├── Procfile
├── config
│   ├── puma.rb
│   └── vhost.yml
└── config.ru
```

#### Bundler

You can also use bundler to manage the gem; add this into your `Gemfile`

```
gem 'attache'
```

then execute

```
bundle install
bundle exec attache start -c web=1 -p 9292
```

NOTE: some config files will be written into your current directory (see RubyGems above)

#### Source code

You can checkout the source code and run it like a regular [a Procfile-based app](https://ddollar.github.io/foreman/):

```
git clone https://github.com/choonkeat/attache.git
cd attache
bundle install
foreman start -c web=1 -p 9292
```

See [foreman](https://github.com/ddollar/foreman) for more details.

## Configuration

`LOCAL_DIR` is where your local disk cache will be. By default, attache will use a system assigned temporary directory which may not be the same everytime you run attache.

`CACHE_SIZE_BYTES` determines how much disk space will be used for the local disk cache. If the size of cache exceeds, least recently used files will be evicted after `CACHE_EVICTION_INTERVAL_SECONDS` duration.

#### Asynchronous delete

By default `attache` will delete files from cloud storage using the lightweight, async processing library [sucker_punch](https://github.com/brandonhilkert/sucker_punch). This requires no additional setup (read: 1x free dyno).

However if you prefer a more durable queue for reliable uploads, configuring `REDIS_PROVIDER` or `REDIS_URL` will switch `attache` to use a `redis` queue instead, via `sidekiq`. [Read Sidekiq's documentation](https://github.com/mperham/sidekiq/wiki/Using-Redis#using-an-env-variable) for details on these variables.

If for some reason you'd want the cloud storage delete to be synchronous, set `INLINE_JOB=1` instead.

#### Virtual Host Cloud Storage

`attache` uses a different config (and backup files into a different cloud service) depending on the request hostname that it was accessed by.

This means a single attache server can be the workhorse for different apps. Refer to `config/vhost.example.yml` file for configuration details.

At boot time, `attache` server will first look at `VHOST` environment variable. If that is missing, it will load the content of `config/vhost.yml`. If neither exist, the `attache` server run in development mode; uploaded files are only stored locally and may be evicted to free up disk space.

If you do not want to write down sensitive information like aws access key and secrets into a `config/vhost.yml` file, you can convert the entire content into `json` format and assign it to the `VHOST` environment variable instead.

```
# bash
export VHOST=$(bundle exec rake attache:vhost)

# heroku
heroku config:set VHOST=$(bundle exec rake attache:vhost)
```

#### Virtual Host Authorization

By default `attache` will accept uploads and delete requests from any client. Set `SECRET_KEY` to ensure attache only receives upload (and delete commands) from your own app.

To most app developers *using* attache in your rails app through a library like [attache-rails gem](https://github.com/choonkeat/attache-rails), how this work may not matter. But if you are developing attache itself or writing a client library for attache, then read on.

#### Virtual Host Authorization (Developer)

When `SECRET_KEY` is set, `attache` will require a valid `hmac` parameter in the upload request. Upload and Delete requests will be refused with `HTTP 401` error unless the `hmac` is correct.

The additional parameters required for authorized request are:

* `uuid` is a uuid string
* `expiration` is a unix timestamp of a future time. the significance is, if the timestamp has passed, the upload will be regarded as invalid
* `hmac` is the `HMAC-SHA1` of the `SECRET_KEY` and the concatenated value of `uuid` and `expiration`

i.e.

``` ruby
hmac = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), SECRET_KEY, uuid + expiration)
```

## APIs

The attache server is a reference implementation of these interfaces. If you write your own server, [compatibility can be verified by running a test suite](https://github.com/choonkeat/attache_api#testing-against-an-attache-compatible-server).

#### Upload

Users will upload files directly into the `attache` server from their browser, bypassing the main app.

> ```
> PUT /upload?file=image123.jpg
> ```
> file content is the http request body

or

> ```
> PUT /upload?data=data:image/jpeg;base64,/9j/4QBiR....
> ```

The main app front end will receive a unique `path` for each uploaded file - the only information to store in the main app database.

> ```
> {"path":"pre/fix/image123.jpg","content_type":"image/jpeg","geometry":"1920x1080"}
> ```
> json response from attache after upload.

#### Download

Whenever the main app wants to display the uploaded file, constrained to a particular size, it will use a helper method provided by the `attache` lib. e.g. `embed_attache(path)` which will generate the necessary, barebones markup.

> ```
> <img src="https://example.com/view/pre/fix/100x100/image123.jpg" />
> ```
> use [the imagemagick resize syntax](http://www.imagemagick.org/Usage/resize/) to specify the desired output.
>
> make sure to `escape` the geometry string.
> e.g. for a hard crop of `50x50#`, the url should be `50x50%23`
>
> ```
> <img src="https://example.com/view/pre/fix/50x50%23/image123.jpg" />
> ```
> requesting for a geometry of `original` will return the uploaded file. this works well for non-image file uploads.
> requesting for a geometry of `remote` will skip the local cache and serve from cloud storage.

* Attache keeps the uploaded file in the local harddisk (a temp directory)
* Attache will also upload the file into cloud storage if `FOG_CONFIG` is set
* If the local file does not exist for some reason (e.g. cleared cache), it will download from cloud storage and store it locally
* When a specific size is requested, it will generate the resized file based on the local file and serve it in the http response
* If cloud storage is defined, local disk cache will store up to a maximum of `CACHE_SIZE_BYTES` bytes. By default `CACHE_SIZE_BYTES` will 80% of available diskspace

#### Delete

> ```
> DELETE /delete
> paths=image1.jpg%0Aprefix2%2Fimage2.jpg%0Aimage3.jpg
> ```

Removing 1 or more files from the local cache and remote storage can be done via a http `POST` or `DELETE` request to `/delete`, with a `paths` parameter in the request body.

The `paths` value should be delimited by the newline character, aka `\n`. In the example above, 3 files will be requested for deletion: `image1.jpg`, `prefix2/image2.jpg`, and `image3.jpg`.

#### Backup

> ```
> POST /backup
> paths=image1.jpg%0Aprefix2%2Fimage2.jpg%0Aimage3.jpg
> ```

This feature might be known as `promote` in other file upload solutions. `attache` allows client app to `backup` uploaded images to another bucket for longer term storage.

Copying 1 or more files from the default remote storage to the backup remote storage (backup) can be done via a http `POST` request to `/backup`, with a `paths` parameter in the request body.

The `paths` value should be delimited by the newline character, aka `\n`. In the example above, 3 files will be requested for backup: `image1.jpg`, `prefix2/image2.jpg`, and `image3.jpg`.

If backup remote storage is not configured, this API call will be a noop. If configured, the backup storage must be accessible by the same credentials as default cloud storage as the system. Please refer to the `BACKUP_CONFIG` configuration illustrated in `config/vhost.example.yml` file in this repository.

By default, `backup` operation is performed synchronously. Set `BACKUP_ASYNC` environment variable to make it follow the same synchronicity as `delete`

The main reason to configure a backup storage is to make the default cloud storage auto expire files; mitigating [abuse](https://github.com/choonkeat/attache/issues/13). You should consult the documentation of your cloud storage provider on how to setup auto expiry, e.g. [here](https://aws.amazon.com/blogs/aws/amazon-s3-object-expiration/) or [here](https://cloud.google.com/storage/docs/lifecycle)

## License

MIT
