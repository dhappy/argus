namespace :import do
  desc 'Import data from external sources'

  task(pathtest: :environment) do |t, args|
    path = [:one, :two, :three]
    
  end

  task(
    :gutenepubs,
    [:dir] => [:environment]
  ) do |t, args|
    require 'zip'

    puts "Searching: #{args[:dir]}/*/*-images.epub"
    outdir = "gutenepubs-#{Time.now.iso8601}"
    puts " For: #{outdir}"

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

      puts ' Creating FS:'
      basedir = "/#{outdir}/project/Gutenberg/id/#{guten_id}"
      system('ipfs', 'files', 'mkdir', '-p', basedir)
      if cover
        system('ipfs', 'files', 'cp', "/ipfs/#{coverId}", "/#{basedir}/#{cover}")
      end
      system('ipfs', 'files', 'cp', "/ipfs/#{bookId}", "/#{basedir}/index.epub")

      dirId = nil
      IO.popen(['ipfs', 'files', 'stat', basedir], 'r+') do |cmd|
        dirId = cmd.readlines.first&.chomp
      end
      puts " Done: #{dirId}"

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
            pgterms: 'http://www.gutenberg.org/2009/pgterms/'
          )
          if !asNodes && res.size == 0
            nil
          elsif !asNodes && res.size === 1
            Nokogiri::HTML.parse(res.to_s).text # uses & escapes
          else
            res
          end
        }

        add = ->(paths) {
          paths.each do |path|
            next if path.any?{ |p| p.nil? || p.empty? }

            system('ipfs', 'files', 'mkdir', '-p', "/#{outdir}/#{File.join(path[0..-2])}")
            system('ipfs', 'files', 'cp', "/ipfs/#{dirId}", "/#{outdir}/#{File.join(path)}")
          end
        }

        bibauthors = xpath.call('//dcterms:creator//pgterms:name/text()', true)
        bibauthor = bibauthors.map(&:to_s).join(' & ')
        authors = bibauthors.map do |a|
          a.to_s.sub(/^(.+?), (.+)$/, '\2 \1')
          .gsub(/\s+\(.*?\)\s*/, ' ')
        end
        author = authors.join(' & ')
        title = xpath.call('//dcterms:title/text()').gsub(/\r?\n/, ' ')
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

        add.call([
          ['book', 'by', author, title],
          ['book', 'bibliographically', bibauthor, title],
          ['book', 'entitled', fulltitle],
          ['book', 'language', lang, fulltitle]
        ])
        add.call(subs.map{ |s| ['subject'] + s + [fulltitle] })
        add.call(shelves.map do |s|
          %w[project Gutenberg bookshelf] + [s, fulltitle]
        end)
      end
    end
  end

  task(
    :json,
    [:file, :award] => [:environment]
  ) do |t, args|
    Rails.logger.level = 0

    award = Award.find_or_create_by(
      name: args[:award]
    )
    data = File.open(args[:file]) do |f|
      json = JSON.parse(f.read)
      entries = Entry.parse(json, award)
    end
  end
end