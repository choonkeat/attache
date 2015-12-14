require 'attache'

use Attache::Delete
use Attache::Upload
use Attache::Download
use Attache::Tus::Upload
use Attache::Backup
use Rack::Static, urls: ["/"], root: Attache.publicdir, index: "index.html"

run proc {|env| [200, {}, []] }
