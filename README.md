# 🦚 Argus 🦚

This repository contains primarily rake tasks used to create the data structures that [Mïmis](//github.com/dhappy/mimis) consumes.

The heart of the program is a Neo4j database with the Awards and Series information from the [Internet Speculative Fiction Database](//isfdb.org).

The work of populating the graph and writing to IPFS is done by various rake tasks.

## Quickstart (*nix)

* `git clone https://github.com/dhappy/argus`
* `cd argus`
* `alias isotime='date +%Y-%m-%d@%H:%M:%S%:z'`
* `function rlog() { rake $1 | tee log/$1.$(isotime).log; }`
* `screen`
* `rlog isfdb:awards`
* `⌘^a c`
* `rlog isfdb:series`
* `⌘^a c`
* `rlog isfdb:covers`
* `⌘^a d`
* `screen -r` # after many hours have passed and see how much data has been integrated into the graph.
* `rake export:awards` # after everything is loaded

## Console

Neo4j has a database console you can access by running `rake neo4j:start` and visiting `http://localhost:7474`.

## Rake

Assumes that a dump of [the Internet Speculative Fiction Database](http://www.isfdb.org/wiki/index.php/ISFDB_Downloads) is loaded into MySql in the `isfdb` database.

### rake isfdb:awards

Saves the award year, category and books into the graph. The format of the graph is:

`(:Award)-[:YR]->(:Year)-[:CAT]->(:Category)-[:NOM]->(:Book|:Movie)`

* There is a `result` property on [the `Nominated` relation](app/models/nominated.rb) that is either:
  * The number that they placed in the competition.
  * Text strings like `Not on Ballot: Insufficient Nominations` describing a special situation.
  * `NULL` is the order is unspecified.

### rake isfdb:series

Saves the series nesting, contents and order into the graph. The format is:

`(:Series)-[:SUB*]->(:Series)-[:HAS]->(:Book|:Movie)<-[CRTR]-(:Creators)`

* `Creators` represents all the creators for a work.
* There is a `rank` associated `Contains` relations: `MATCH (s:Series)-[h:HAS]->(b:Book) ORDER BY h.rank RETURN s`

### rake isfdb:covers

Saves the covers isbn and image url into the graph. The format is:

`(:Book)-[:PUB]->(:Version)-[:CVR]->(:Cover)`

* This ISBN uniquifies a version.

### rake argus:images

Finds Content nodes with a url, but no IPFS id, then downloads the url and inserts it into IPFS. This works in conjunction with `isfdb:covers` to collect the cover images referenced in the database,

### rake epubs:create

Spiders a directory tree and where there is an index.html, but no index.epub, it creates the necessary files for a basic epub and zips the directory to index.epub.

There's a git repo created for every position in the corpus (the Hugo and Nebula Award literary nominees). In that directory is an exploded EPUB (EPUB is just a particularly structured ZIP archive).

### rake epubs:git

Spiders and in directories with an index.epub the file is exploded, the results added to git, and the commit [pushed to IPFS](//github.com/dhappy/git-remote-igis).

### rake export:covers

Creates a regular unix filesystem of the form `book/by/#{author}/#{title}/#{isbn}.#{type}` from the IPFS ids stored in `Cover` objects.

### rake git:cmd['add -r .']

Spiders and, for each repository that is found, add all the files.

### rake git:commit['importing images 🖼']

Spiders and, for each repository that is found, commits with the given message and pushes to IPFS.

### rake export:ipfs

Creates a mutable filesystem with all the award winning books with content.

### rake export:awards

### bundle exec rails server

### [/review?count=100&skip=0]

For books without a `-[:RPO]->` link, check the directory `../.../trainpacks/` for files matching the pattern `*#{author}*#{title}*` or `*#{title}*#{author}*`.

The page has an `⏩ Injest ⏭` button for each found file that will copy the given file to `../.../book/by/#{author}/#{title}/`.

Zip and rar files are uncompressed. If there is a single (`html`|`epub`|`rtf`|`mobi`|`lit`) file it is renamed to `index.#{ext}`.

`index.htm` is renamed to `index.html` which has an acceptably small chance of breaking a multipage document.
