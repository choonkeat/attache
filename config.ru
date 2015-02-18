require './boot.rb'

use Attache::Upload
use Attache::Download
use Rack::Static, urls: ["/"], root: "public", index: "index.html"

run proc {|env| [200, {}, []] }
