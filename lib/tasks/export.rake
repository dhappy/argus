namespace :export do
  desc 'Export award winners to IPFS'
  task(ipfs: :environment) do |t, args|
    require 'ipfs/client'

    basedir = "epubs-#{Time.now.iso8601}"
    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (n:Context)-[:SUB*]->(m:Context)-[f:FOR]->(book:Book) WHERE n.name = 'award' AND (book:Book)-[:RPO]->() RETURN DISTINCT book"
    )
    q.each do |ret|
      book = ret.book

      next unless(
        book.author.present? && book.title.present? \
        && book.title != 'untitled' && book.author != '(********)'
      )
      path = %W[book entitled #{book.title}]
      path = %w[book by] + [book.author, book.title] if book.author.present?
      path.map!{ |p| p.gsub('%', '%25').gsub('/', '%2F') }
      datadir = "/#{basedir}/#{path.join('/')}"

      puts "#{book.title}, by #{book.author}"
      puts "  To: #{datadir}"

      system('ipfs', 'files', 'mkdir', '-p', datadir)

      Tempfile.open('mimis', "#{Rails.root}/tmp", encoding: 'ascii-8bit') do |file|
        file.write({
          author: book.author, title: book.title,
        }.to_json)
        file.flush
        mimis = IPFS::Client.default.add(file.path)
        system('ipfs', 'files', 'cp', "/ipfs/#{mimis.hashcode}", "#{datadir}/mimis.json")
      end

      if false && book.content
        puts "  Adding: #{datadir}/index.epub"
        system('ipfs', 'files', 'cp', "/ipfs/#{book.content.ipfs_id}", "#{datadir}/index.epub")
      end

      if book.repo
        puts "  Adding: #{datadir}/repo/"
        system('ipfs', 'files', 'cp', "/ipfs/#{book.repo.ipfs_id}", "#{datadir}/repo")
      end

      covers = book.versions(rel_length: :any).cover.to_a
      covers = [book.cover] if covers.empty?
      covers.select!{ |c| c&.ipfs_id.present? }
      covers.uniq!(&:ipfs_id)
      if covers.any?
        system('ipfs', 'files', 'mkdir', '-p', "#{datadir}/covers/")
        covers.each.with_index(1) do |cover, idx|
          filename = "#{idx}.#{cover.mimetype.split('/').pop.split('+').first}"
          puts "  Adding: #{datadir}/covers/#{filename}"
          system('ipfs', 'files', 'cp', "/ipfs/#{cover.ipfs_id}", "#{datadir}/covers/#{filename}")
        end
      end
    end
  end

  desc 'Export awards context tree to JSON'
  task(awards: :environment) do |t, args|
    q = Neo4j::ActiveBase.current_session.query(
      "MATCH path = (n:Context)-[:SUB]->(p:Context)-[s:SUB*]->(m:Context)-[f:FOR]->(o:Book) WHERE n.name = '∅' AND p.name = 'award' RETURN DISTINCT path"
    )
    links = q.map do |ret|
      book = Book.find(ret.path.nodes.pop.properties[:uuid])
      nodes = ret.path.nodes
      nodes.shift # remove ∅
      from = nodes.map{ |n| n.properties[:name] }
      to = %W[book entitiled #{book.title}]
      to = %w[book by] + [book.author, book.title] if book.author.present?
      { from: from, to: to, type: :link }
    end
    filename = "#{Rails.root}/tmp/award_links.#{Time.now}.json"
    puts "Writing: #{filename}"
    File.open(filename, 'w'){ |f| f.write(links.to_json) }
  end

  def fname(str)
    str.gsub('%', '%25').gsub('/', '%2F').gsub("\x00", '%00')[0..254]
  end

  desc 'Export cover images to [dir] in book/by/#{author}/#{title}/covers/#{isbn}.#{ext}'
  task(:covers, [:dir] => [:environment]) do |t, args|
    require 'ipfs/client'

    dir = args[:dir] || '../...'

    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (book:Book) WHERE (book:Book)-[:CVR]->() OR (book:Book)-->()-[:CVR]->() RETURN DISTINCT book"
    )
    q.each do |ret|
      book = ret.book

      covers = book.versions(rel_length: :any).cover.to_a
      covers = [book.cover] if covers.empty?
      covers.select!{ |c| c&.ipfs_id.present? }
      covers.uniq!(&:ipfs_id)
      if covers.any?
        covers.each.with_index(1) do |cover, idx|
          cover.versions.each do |version|
            filename = "#{version.isbn}.#{cover.mimetype.split('/').pop.split('+').first}"

            dirname = "#{dir}/book/by/#{fname(book.author)}/#{fname(book.title)}/covers"
            fullname = "#{dirname}/#{filename}"
            if File.exists?(fullname)
              puts "  Skipping: #{fullname} (#{cover.ipfs_id})"
            else
              puts "  Adding: #{fullname} (#{cover.ipfs_id})"
              FileUtils.mkdir_p(dirname)
              File.open(fullname, 'wb') do |file|
                file.write(IPFS::Client.default.cat(cover.ipfs_id))
              end
            end
          end
        end
      end
    end
  end
end