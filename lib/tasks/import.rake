namespace :import do
  desc 'Import data from external sources'

  task(:gutenepubs, [:dir] => [:environment]) do |t, args|
    require 'zip'

    puts "Searching: #{args[:dir]}/*/*-images.epub"

    Dir.glob("#{args[:dir]}/*").each.with_index do |dir, idx|
      next unless File.directory?(dir)
      ls = Dir.glob("#{dir}/*-images.epub")
      ls = Dir.glob("#{dir}/*.epub") if ls.empty?
      epub = ls.first
      guten_id = dir.match(/(\d+)$/).try(:[], 1)

      unless epub && guten_id
        puts "Error: No epub (#{guten_id}) in #{dir}"
        next
      end

      if File.new(epub).size == 0
        puts "Error: #{epub} is empty"
        next
      end

      puts "Importing: #{epub} (#{idx})"
      path = Pathname.new(epub)
      FileUtils.chdir(File.dirname(epub))

      cover = Dir.glob('cover.*').first

      if cover
        puts " Found: #{cover}"
      else
        begin
          Zip::File.open(File.basename(epub)) do |epub_zip|
            metazip = epub_zip.glob('META-INF/container.xml').first
            raise RuntimeError, 'No Meta Container' unless metazip
            meta = Nokogiri::parse(metazip.get_input_stream)
            root = meta.css('rootfile @full-path').to_s # ToDo: Handle multiple
            doc = epub_zip.glob(root).first
            raise RuntimeError, 'No Root Doc' unless doc
            content = Nokogiri::parse(doc.get_input_stream)
            coverid = content.css('meta[@name="cover"] @content').to_s
            if coverid.empty?
              raise RuntimeError, "No cover for #{guten_id}"
            else
              item = content.css("item##{coverid}")
              coverref = item.attribute('href').to_s
              type = item.attribute('media-type').to_s
              cover = "cover.#{type.split('/').last}"
              rootdir = File.dirname(root)
              rootdir += '/' unless rootdir.empty? 
              doc = epub_zip.glob("#{rootdir}#{coverref}").first
              unless doc
                raise RuntimeError, "Missing in zip: #{rootdir}#{coverref}"
              end
              doc.extract(cover)
            end
          end
        rescue RuntimeError => err
          puts "Error: #{err.message}"
        end
      end

      unless cover
        puts ' No Cover'
      else
        print ' Then, import cover into IPFS:'
        coverId = nil
        IO.popen(['ipfs', 'add', cover], 'r+') do |cmd|
          out = cmd.readlines.last
          coverId = out&.split.try(:[], 1)
          unless $?.success? && coverId
            puts "Error: Cover Import of #{guten_id} (#{coverId})"
            next
          end
        end
        puts " Done: #{coverId}"
      end

      print ' Then, import book into IPFS:'
      bookId = nil
      IO.popen(['ipfs', 'add', epub], 'r+') do |cmd|
        out = cmd.readlines.last
        bookId = out&.split.try(:[], 1)
        unless $?.success? && bookId
          puts "Error: IPFS Import of #{guten_id} (#{bookId})"
          next
        end
      end
      puts " Done: #{bookId}"

      metadata = Dir.glob('*.rdf').try(:[], 0)

      puts ' Next, read the metadata:'
      File.open(metadata) do |file|
        doc = Nokogiri::XML(file)

        xpath = ->(path, asNodes = false) {
          res = doc.xpath(
            path,
            dc: 'http://purl.org/dc/elements/1.1/',
            opf: 'http://www.idpf.org/2007/opf',
            dcterms: 'http://purl.org/dc/terms/',
            rdf: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
            pgterms: 'http://www.gutenberg.org/2009/pgterms/',
            marcrel: 'http://id.loc.gov/vocabulary/relators/'
          )
          if !asNodes && res.size == 0
            nil
          elsif !asNodes && res.size === 1
            Nokogiri::HTML.parse(res.to_s).text # uses & escapes
          else
            res
          end
        }

        bibauthors = xpath.call('//dcterms:creator//pgterms:name/text()', true)
        if bibauthors.empty?
          bibauthors = xpath.call('//marcrel:*//pgterms:name/text()', true)
        end
        bibauthor = bibauthors.map(&:to_s).join(' & ')
        authors = bibauthors.map do |a|
          a.to_s.sub(/^(.+?), (.+)$/, '\2 \1')
          .gsub(/\s+\(.*?\)\s*/, ' ')
        end
        author = authors.join(' & ')
        title = xpath.call('//dcterms:title/text()')
        if title.is_a?(Nokogiri::XML::NodeSet)
          title = title.map(&:to_s).join(' / ')
        end
        title.gsub!(/\r?\n/, ' ')
        lang = xpath.call('//dcterms:language//rdf:value/text()')
        if lang.is_a?(Nokogiri::XML::NodeSet)
          lang = "#{lang[0..-2].map(&:to_s).join(', ')} & #{lang[-1]}"
        end
        subs = (
          xpath.call('//dcterms:subject', true).map do |sub|
            val = sub.xpath('.//rdf:value/text()')
            val = val.to_s.split(/\s+--\s+/)
            taxonomy = sub.xpath('.//dcam:memberOf/@rdf:resource').to_s
            if taxonomy == 'http://purl.org/dc/terms/LCC'
              val = ['Library of Congress', 'code'] + val
            end
            val
          end
        )
        shelves = (
          xpath.call('//pgterms:bookshelf//rdf:value/text()', true).map do |shelf|
            shelf.to_s.sub(/\s*\(Bookshelf\)/, '')
          end
        )
        fulltitle = "#{title}#{author && ", by #{author}"}"

        root = Context.merge(name: '∅')

        add = ->(paths) {
          paths.each do |path|
            curr = root
            cs = path.map do |p|
              child = curr.contexts.find_by(name: p)
              child ||= Context.create(name: p)
              curr = child
            end
            root.contexts << cs[0]
            cs[0..-2].each.with_index do |c, i|
              c.contexts << cs[i + 1]
            end
            book = Book.merge(title: title, author: author)
            cs[-1].for << book
            if coverId
              book.cover = Content.merge(mimetype: 'image/*', ipfs_id: coverId)
            end
            book.content = Content.merge(mimetype: 'application/epub+zip', ipfs_id: bookId)
          end
        }

        add.call([
          ['book', 'by', author],
          ['book', 'bibliographically', bibauthor],
          ['book', 'entitled', fulltitle],
          ['book', 'language', lang],
          ['project', 'Gutenberg', 'id', guten_id]
        ])
        add.call(subs.map{ |s| ['subject'] + s })
        add.call(shelves.map do |s|
          %w[project Gutenberg bookshelf] + [s]
        end)
      end
    end
  end

  desc 'Recursively find all epubs, save doc and cover to IPFS and Neo4J'
  task(:epubs, [:basedir] => [:environment]) do |t, args|
    require 'ipfs/client'
    
    root = Context.merge(name: '∅')

    add = ->(epub) {
      title = epub.metadata.title.to_s
      authors = epub.metadata.creators.map(&:to_s)
      authors = authors.map{ |a| a.sub(/^(.+), (.+)$/, '\2 \1') }
      author = authors.join(' & ')
      path = [
        {name: :book}, {name: :by},
        {name: author, type: :author},
        {name: title, type: :title}
      ]
      puts "Adding: #{path.map{ |p| p[:name] }.join('/')}"
      curr = root
      cs = path.map do |p|
        curr = curr.subcontexts.find_or_create_by(p)
      end
      book = Book.merge(title: title, author: author)
      cs[-1].for << book
      if epub.cover_image
        Tempfile.open('ebook', "#{Rails.root}/tmp", encoding: 'ascii-8bit') do |file|
          file.write(epub.cover_image.read)
          file.flush
          cover = IPFS::Client.default.add(file.path)
          book.cover = Content.merge(
            mimetype: epub.cover_image.media_type,
            ipfs_id: cover.hashcode
          )
        end
      end
      content = IPFS::Client.default.add(epub.epub_file)
      book.content = Content.merge(
        mimetype: 'application/epub+zip', ipfs_id: content.hashcode
      )
    }

    spider = ->(dir) {
      Dir.glob("#{dir}/*").each do |sub|
        if File.directory?(sub)
          spider.call(sub)
        elsif /epub$/.match?(sub)
          begin
            puts sub
            epub = EPUB::Parser.parse(sub)
            add.call(epub)
          rescue Archive::Zip::Error => err
            puts " Error: #{err}"
          end
        end
      end
    }
    basedir = args[:basedir] || "#{Dir.home}/.../book/"
    puts "Starting spider @ #{basedir}"
    spider.call(basedir)
  end

  desc 'Import Entrys from JSON [file, award]'
  task(
    :json,
    [:file, :award] => [:environment]
  ) do |t, args|
    Rails.logger.level = 0

    award = Award.find_or_create_by(name: args[:award])
    data = File.open(args[:file]) do |f|
      json = JSON.parse(f.read)
      entries = Entry.parse(json, award)
    end
  end

  def fname(str)
    str = str.gsub('%', '%25').gsub('/', '%2F').gsub("\x00", '%00')
    str.mb_chars.limit(254).to_s # this causes compatability issues
  end

  desc 'Reimport serialized covers into IPFS'
  task(
    :covers,
    [:dir] => [:environment]
  ) do |t, args|
    require 'ipfs/client'

    dir ||= ""

    basedir = "#{Dir.home}/.../book/"

    Version.all.each do |version|
      version.cover
      dir = "#{fname(version.book.creators.name)}/#{fname(version.book.title)}/covers"
      ipfs.files.mkdir_p(dir)
    end
  end
end