# attache

Users will upload files directly into the `attache` server, by passing the main app. 

The main app front end will receive a unique `path` for each uploaded file - the only information to store in the main app database.

Whenever the main app wants to display the uploaded file, constrained to a particular size, it will use a helper method provided by the `attache` lib. e.g. `embed_attache(path)` which will generate the necessary, barebones markup.

NOTES

* `attache` server accepts all kinds of files, not just images.
* `embed_attache(path)` may render `div`, `img`, `iframe` - whatever is suitable for the file
