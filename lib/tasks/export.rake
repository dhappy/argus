namespace :export do
  desc 'Export award winners to IPFS'
  task(ipfs: :environment) do |t, args|
    require 'ipfs/client'

    basedir = "epubs-#{Time.now.iso8601}"
    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (n:Context)-[:SUB*]->(m:Context)-[f:FOR]->(book:Book) WHERE n.name = 'Hugo Award' AND n.type = 'award' RETURN DISTINCT book"
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
      covers = [book.cover] + book.versions(rel_length: :any).cover.to_a
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
end