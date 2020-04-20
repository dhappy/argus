# 🦚 Argus 🦚

This repository contains primarily rake tasks used to create the data structures that [Mïmis](//github.com/dhappy/mimis) consumes.

The heart of the program is a Neo4j database with the structure `(:Context)-[:SUB*]->(:Context)-[:FOR]->(:Book|Movie)-[:PUB]->(:Version)-[:CVR]->(:Content)`.

The work of populating the graph is done by various rake tasks.

## rake isfdb

Assumes that a dump of [the Internet Speculative Fiction Database](http://www.isfdb.org/wiki/index.php/ISFDB_Downloads) is loaded into MySql in the `isfdb` database.

### rake isfdb:awards

Saves the award year, category and books into the Context graph.

### rake isfdb:covers

Saves the covers isbn and image url into the graph.

### rake argus:images

Finds Content nodes with a url, but no IPFS id, then downloads the url and inserts it into IPFS.

### rake epubs:create

Spiders a directory tree and where there is an index.html, but no index.epub creates the necessary files for a basic epub and zips the directory to index.epub.

### rake epubs:git

Spiders and in directories with an index.epub the file is exploded, the results added to git, and the commit [pushed to IPFS](//github.com/dhappy/git-remote-ipfs).

### rake export:covers

Creates a regular unix filesystem of the form `book/by/#{author}/#{title}/#{isbn}.#{type}` from the IPFS ids stored in Content with a `CVR` relationship.

### rake git:cmd['add -r .']

Spiders and, for each repository that is found, add all the files.

### rake git:commit['importing images 🖼']

Spiders and, for each repository that is found, commits with the given message.

### rake export:ipfs

Creates a mutable filesystem with all the award winning books with content.

### [/review?count=100&skip=0]

For books without a `-[:RPO]->` link, check the directory `../.../trainpacks/` for files matching the pattern `*#{author}*#{title}*` or `*#{title}*#{author}*`.

The page has an `⏩ Injest ⏭` button for each found file that will copy the given file to `../.../book/by/#{author}/#{title}/`.

Zip and rar files are uncompressed. If there is a single (`html`|`epub`|`rtf`|`mobi`|`lit`) file it is renamed to `index.#{ext}`.

`index.htm` is renamed to `index.html` which has an acceptably small chance of breaking a multipage document.