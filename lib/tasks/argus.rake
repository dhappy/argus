desc 'The all-seeing Argus'
namespace :argus do
  # Guarantee this is a valid Unix path
  def fname(str)
    if(str =~ /\// || str =~ /%2f/i) # contains / or %2F, so decode anything containing %2F
      str = str.gsub('%', '%25').gsub('/', '%2F').gsub("\x00", '%00')
    end
    str.mb_chars.limit(254).to_s # this causes compatability issues
  end

  desc 'Insert images into IPFS'
  task(images: :environment) do |t, args|
    require 'net/http'
    require 'ipfs/client'

    q = Cover.as(:c).where(
      'c.cid IS NULL AND c.url IS NOT NULL'
    )

    q.each do |c|
      puts "Processing #{c.url}"
      next unless c.url.present?
      filename = nil

      # w/o the limit it overflows the stack
      c.versions.limit(100).each do |v|
        dir = "../book/by/#{fname(v.book.creators.name)}/#{fname(v.book.title)}/covers"
        base = "#{dir}/#{v.isbn}"
        pat = "#{base}.*"
        puts " Globbing: #{pat}"
        if (glob = Dir.glob(pat)).any?
          puts "  Adding: #{glob.first}: "
          filename = glob.first
        else
          url = c.url.split('|').first
          res = Net::HTTP.get(URI.parse(url))
          ext = url.split('/').last.split('.').pop
          ext ||= 'image'
          ext = :jpeg if ext == 'jpg'
          filename = "#{base}.#{ext}"

          FileUtils.makedirs(dir)
          File.open(filename, mode: 'w', encoding: 'ascii-8bit') do |file|
            file.write(res)
          end
          puts "  Wrote: #{filename}: "
        end

        cid = nil

        IO.popen(['ipfs', 'add', filename], 'r+') do |cmd|
          out = cmd.readlines.last
          cid = out&.split.try(:[], 1)
          unless $?.success? && cid
            puts "Error: IPFS Import of #{filename})"
            next
          end
        end
  
        puts cid

        meta = nil
        IO.popen(
          [
            'exiftool', '-s', '-ImageWidth', '-ImageHeight',
            '-Mimetype', filename
          ],
          'r+'
        ) do |cmd|
          meta = cmd.readlines.reduce({}) do |size, line|
            if match = /^(?<prop>[^:]+\S)\s+:\s+(?<val>\S.+)\r?\n?$/.match(line)
              prop = match[:prop].sub(/^Image/, '').downcase
              size[prop.to_sym] = match[:val]
            end
            size
          end
          unless $?.success?
            puts "Error: EXIF Metadata of #{filename})"
            next
          end
        end
        type = filename.split('.').last # often wrong, but rarely ambiguous
        mimetype = meta[:mimetype] || "image/#{type}"
        puts "  Got Size: #{meta[:width]}✕#{meta[:height]} (#{cid})"

        c.update({
          width: meta[:width], height: meta[:height],
          mimetype: mimetype, cid: cid,
        })
      end
      puts " to #{c.cid} (#{c.mimetype})"
    end
  end

  desc 'Replace HTML entities in book authors and titles'
  task(entities: :environment) do |t, args|
    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (book:Book) WHERE book.title =~ '.*&.*' OR book.author =~ '.*&.*' RETURN DISTINCT book"
    )
    q.each do |ret|
      book = ret.book
      book.title = Nokogiri::HTML.parse(book.title).text
      book.author = Nokogiri::HTML.parse(book.author).text
      book.save
      puts "Fixed #{book.title} by #{book.author}"
    end
  end

  desc 'Generate the context tree for books.'
  task(context: :environment) do |t, args|
    # q = Neo4j::ActiveBase.current_session.query(
    #   'CREATE BTREE INDEX book_names IF NOT EXISTS' \
    #   + ' FOR (b:Book) ON (b.title)'
    # )
    # q = Neo4j::ActiveBase.current_session.query(
    #   'CREATE BTREE INDEX creators_names IF NOT EXISTS' \
    #   + ' FOR (c:Creators) ON (c.name)'
    # )
    root = Root.first
    bookNode = (
      root.query_as(:r)
      .match('(r)-[rel:CHILD { name: "book" }]->(bk)')
      .pluck(:bk)
      .first
    )
    if(bookNode.nil?)
      bookNode = Position.new
      Context.create(
        from_node: root, to_node: bookNode, name: 'book'
      )
    end
    byNode = (
      bookNode.query_as(:bk)
      .match('(bk)-[rel:CHILD { name: "by" }]->(by)')
      .pluck(:by)
      .first
    )
    if(byNode.nil?)
      byNode = Position.new
      Context.create(
        from_node: bookNode, to_node: byNode, name: 'by'
      )
    end

    Creators.all.each do |creators|
      creatorsNode = (
        byNode.query_as(:by)
        .match('(by)-[rel:CHILD]->(cr)')
        .where({ rel: { name: creators.name } })
        .pluck(:cr)
        .first
      )
      if(creatorsNode.nil?)
        creatorsNode = Position.new
        Context.create(
          from_node: byNode, to_node: creatorsNode,
          name: creators.name
        )
      end
      creatorsNode.update(equals: creators)
      creators.books.each do |book|
        bookNode = (
          creatorsNode.query_as(:cr)
          .match('(cr)-[rel:CHILD]->(bk)')
          .where({ rel: { name: book.title } })
          .pluck(:bk)
          .first
        )
        title = "#{book.title} by #{creators.name}"
        if(bookNode.nil?)
          bookNode = Position.new
          Context.create(
            from_node: creatorsNode, to_node: bookNode,
            name: book.title
          )
          puts "Created Path For: #{title}"
        else
          puts "Skipped Existing: #{title}"
        end
        bookNode.update(equals: book)
      end
    end

    awardNode = (
      root.query_as(:r)
      .match('(r)-[rel:CHILD { name: "award" }]->(aw)')
      .pluck(:aw)
      .first
    )
    if(awardNode.nil?)
      awardNode = Position.new
      Context.create(
        from_node: root, to_node: awardNode, name: 'award'
      )
    end
    Award.all.each do |award|
      award.years.each do |year|
        yearNode = (
          awardNode.query_as(:aw)
          .match('(aw)-[rel:CHILD]->(yr)')
          .where({ rel: { name: year.number.to_s } })
          .pluck(:yr)
          .first
        )
        if(yearNode.nil?)
          yearNode = Position.new
          Context.create(
            from_node: awardNode, to_node: yearNode, name: year.number.to_s
          )
        end

        year.categories.each do |category|
          catNode = (
            yearNode.query_as(:yr)
            .match('(yr)-[rel:CHILD]->(ct)')
            .where({ rel: { name: category.title } })
            .pluck(:ct)
            .first
          )
          if(catNode.nil?)
            catNode = Position.new
            Context.create(
              from_node: yearNode, to_node: catNode, name: category.title
            )
          end

          category.nominees.each do |work|
            title = "#{work.title} by #{work.creators.name}"
            searchWorkNode = (
              catNode.query_as(:aw)
              .match('(ct)-[rel:CHILD]->(wk)')
              .where({ rel: { name: title } })
              .pluck(:wk)
              .first
            )
            # All books have an entry, so this should be set
            referencedWorkNode = work.position
            if(
              searchWorkNode.present? \
              && referencedWorkNode.present? \
              && searchWorkNode != referencedWorkNode
            )
              puts "Error: Multiple Work Positions: #{searchWorkNode.uuid} & #{referencedWorkNode.uuid}"
            end
            if(searchWorkNode.present?)
              puts "Skipped Existing: (#{award.shortname}): #{title}"
            else
              workNode = referencedWorkNode || Position.new
              Context.create(
                from_node: catNode, to_node: workNode, name: title
              )
              if(workNode != referencedWorkNode)
                work.update(equals: workNode)
              end
              puts "Created Path For: (#{award.shortname}): #{title}"
            end
          end
        end
        awardNode
        # /award/Hugo Award/1973/Best Novel/1
        # /award/Hugo Award/1973/Best Novel/Crake by Margret Atwood
        # /award/Hugo Award/Best Novel/1973/↑
      end
    end

    # q = Neo4j::ActiveBase.current_session.query(
    #   'MATCH (creators:Creators)-->(book:Book)' \
    #   + ' MERGE (:Root)-[:CHILD {name: "book"}]->' \
    #   + ' (:Position)-[:CHILD {name: "by"}]->' \
    #   + ' (:Position)-[:CHILD {name: creators.name}]->' \
    #   + ' (pc:Position)-[:CHILD {name: book.title}]->' \
    #   + ' (pb:Position)' \
    #   + ' MERGE (pc)-[:EQUALS]->(creators)' \
    #   + ' MERGE (pb)-[:EQUALS]->(book)'
    # )
    # q = Neo4j::ActiveBase.current_session.query(
    #   'MATCH (award:Award)-->(year:Year)-->' \
    #   + ' (category:Category)-->(book:Book)' \
    #   + ' <--(creators:Creators)' \
    #   + ' MERGE (:Root)-[:CHILD {name: "award"}]->' \
    #   + ' (:Position)-[:CHILD {name: award.title}]->' \
    #   + ' (:Position)-[:CHILD {name: year.number}]->' \
    #   + ' (:Position)-[:CHILD {name: category.title}]->' \
    #   + ' (:Position)-[:CHILD' \
    #   + ' {name: book.title + " by " + creators.name}]->' \
    #   + ' (pb:Position)' \
    #   + ' MERGE (pb)-[:EQUALS]->(book)'
    # )
    # q = Neo4j::ActiveBase.current_session.query(
    #   'MATCH (series)-->(book:Book)' \
    #   + ' <--(creators:Creators)' \
    #   + ' MERGE (:Root)-[:CHILD {name: "series"}]->' \
    #   + ' (:Position)-[:CHILD {name: award.title}]->' \
    #   + ' (:Position)-[:CHILD {name: year.number}]->' \
    #   + ' (:Position)-[:CHILD {name: category.title}]->' \
    #   + ' (:Position)-[:CHILD' \
    #   + ' {name: book.title + " by " + creators.name}]->' \
    #   + ' (pb:Position)' \
    #   + ' MERGE (pb)-[:EQUALS]->(book)'
    # )
  end

  desc 'Find Git repositories, export to IPFS, and save the CID'
  task(:repos, [:dir] => [:environment]) do |t, args|
    save = ->(dir) {
      parts = dir.split('/')
      author = CGI.unescape(parts[-2])
      title = CGI.unescape(parts[-1])
      book = Book.find_by(author: author, title: title)
      print "#{title}, by #{author} (#{book&.uuid}): "
      unless book
        puts "Not Found"
      else
        FileUtils.chdir(dir) do
          IO.popen(['git', 'push', 'ipfs::', 'master'], err: [:child, :out]) do |io|
            lines = io.readlines
            line = lines.find{ |l| /^Pushed to IPFS as /.match?(l) }
            unless line
              puts "No CID: Error On Import?"
            else
              cid = line.match(/\.*ipfs:\/\/(.*)\e.*/)[1]
              puts cid
              system('ipfs', 'pin', 'add', '-r', cid)
              book.repo = Content.find_or_create_by(ipfs_id: cid)
            end
          end
        end
      end
    }

    spider = ->(dir) {
      Dir.glob("#{dir}/*").each do |sub|
        if File.directory?("#{sub}/.git")
          save.call(sub)
        elsif File.directory?(sub)
          spider.call(sub)
        end
      end
    }

    dir = args[:dir] || '../.../book/by'
    spider.call(dir)
  end
end