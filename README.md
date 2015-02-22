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

* Attache keeps the uploaded file in the local harddisk (a temp directory).
* Attache will also upload the file into cloud storage if `FOG_CONFIG` is set
* If the local file does not exist for some reason (e.g. cleared cache), it will download from cloud storage and store it locally
* When a specific size is requested, it will generate the resized file based on the local file and serve it in the http response
* If the resized file already exist, it will be served directly without further resizing.

## Configure

Set your `FOG_CONFIG` environment variable to a json string, e.g.

```
export FOG_CONFIG='{"provider":"AWS", "aws_access_key_id":"REPLACE", "aws_secret_access_key":"REPLACE", "s3_bucket":"demo" }'
```

## Authorization

When `SECRET_KEY` environment variable is provided, `attache` will require a valid `hmac` parameter. Uploads will be refused with `HTTP 401` error unless the `hmac` is correct.

Uploads need these additional parameters:

* `uuid` is a uuid string
* `expiration` is a unix timestamp of a future time. the significance is, if the timestamp has passed, the upload will be regarded as invalid
* `hmac` is the `HMAC-SHA1` of the `SECRET_KEY` and the concatenated value of `uuid` and `expiration`

i.e.

``` ruby
hmac = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), SECRET_KEY, uuid + expiration)
```

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
