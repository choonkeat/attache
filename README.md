# attache

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

Users will upload files directly into the `attache` server from their browser, bypassing the main app.

> ```
> PUT /upload?file=image123.jpg
> ```
> file content is the http request body

The main app front end will receive a unique `path` for each uploaded file - the only information to store in the main app database.

> ```
> {"path":"pre/fix/image123.jpg","content_type":"image/jpeg","geometry":"1920x1080"}
> ```
> json response from attache after upload.

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

* Attache keeps the uploaded file in the local harddisk (a temp directory).
* Attache will also upload the file into cloud storage if `FOG_CONFIG` is set
* If the local file does not exist for some reason (e.g. cleared cache), it will download from cloud storage and store it locally
* When a specific size is requested, it will generate the resized file based on the local file and serve it in the http response
* If cloud storage is defined, local disk cache will store up to a maximum of `CACHE_SIZE_BYTES` bytes. By default `CACHE_SIZE_BYTES` will 80% of available diskspace.

## Configure

Set your `FOG_CONFIG` environment variable to a json string, e.g.

```
export FOG_CONFIG='{"provider":"AWS", "aws_access_key_id":"REPLACE", "aws_secret_access_key":"REPLACE", "bucket":"demo" }'
```

Refer to [fog documentation](http://fog.io/storage/) for configuration details of `Fog::Storage.new`

Non-standard keys in `FOG_CONFIG` are:

- `bucket` is the name of the s3 "bucket", rackspace "container", etc..
- `file_options` is the options passed into Fog API `files.create()`

## Authorization

Without `SECRET_KEY` environment variable, attache works out-of-the-box: allowing uploads from any client.

When `SECRET_KEY` is set, `attache` will require a valid `hmac` parameter in the upload request. Uploads will be refused with `HTTP 401` error unless the `hmac` is correct.

Upload request need additional parameters:

* `uuid` is a uuid string
* `expiration` is a unix timestamp of a future time. the significance is, if the timestamp has passed, the upload will be regarded as invalid
* `hmac` is the `HMAC-SHA1` of the `SECRET_KEY` and the concatenated value of `uuid` and `expiration`

i.e.

``` ruby
hmac = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), SECRET_KEY, uuid + expiration)
```

NOTE: these authorization options can be transparently hooked up with the help of integration libraries. e.g. [attache_rails gem](https://github.com/choonkeat/attache_rails)

## Run

Run it like any Rack app

```
rackup
```

## Heroku ready

Set your `FOG_CONFIG` config, git push to deploy

## Todo

* `attache` server should accept all kinds of files, not just images.
* `embed_attache(path)` may render `div`, `img`, `iframe` - whatever is suitable for the file
* cloud upload should be async via `sidekiq`
* `FOG_CONFIG` should allow for "Virtual Host", where different hostname can use a different cloud storage.

## License

MIT
