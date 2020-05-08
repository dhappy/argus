namespace :export do
  desc 'Export award winners to IPFS'
  task(ipfs: :environment) do |t, args|
    require 'ipfs/client'

    basedir = "epubs-#{Time.now.iso8601}"
    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (n:Context)-[:SUB*]->(m:Context)-[f:FOR]->(book:Book) WHERE n.type = 'award' AND n.name='Hugo Award' AND (book:Book)-[:RPO]->() RETURN DISTINCT book"
    )
    idx = 0 # .with_index(1) fails
    q.each do |ret|
      book = ret.book
      idx += 1

      next unless(
        book.author.present? && book.title.present? \
        && book.title != 'untitled' && book.author != '(********)'
      )
      path = %W[book entitled]
      path = %w[book by] + [book.author] if book.author.present?
      path.map!{ |p| p.gsub('%', '%25').gsub('/', '%2F') }
      datadir = "/#{basedir}/#{path.join('/')}"
      title = book.title.gsub('%', '%25').gsub('/', '%2F')

      combined = "#{book.title} by #{book.author}"
      raise RuntimeError, "No Repo: #{combined}" unless book.repo

      puts "#{ActionController::Base.helpers.number_with_delimiter(idx)}: #{combined} (#{book.repo.ipfs_id})"
      system('ipfs', 'files', 'mkdir', '-p', datadir)

      datadir = "#{datadir}/#{title}"
      puts "  Adding: #{datadir}/"
      system('ipfs', 'files', 'cp', "/ipfs/#{book.repo.ipfs_id}", datadir)

      Tempfile.open('mimis', "#{Rails.root}/tmp", encoding: 'ascii-8bit') do |file|
        file.write({
          author: book.author, title: book.title,
        }.to_json)
        file.flush
        mimis = IPFS::Client.default.add(file.path)
        system('ipfs', 'files', 'cp', "/ipfs/#{mimis.hashcode}", "#{datadir}/mimis.json")
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
    str = str.gsub('%', '%25').gsub('/', '%2F').gsub("\x00", '%00')
    str.mb_chars.limit(254).to_s # this causes compatability issues
  end

  desc 'Export cover images to [dir] in book/by/#{author}/#{title}/covers/#{isbn}.#{ext}'
  task(:coverimgs, [:dir] => [:environment]) do |t, args|
    require 'ipfs/client'

    dir = args[:dir] || '../...'

    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (book:Book) WHERE (book:Book)-[:CVR]->() OR (book:Book)-->()-[:CVR]->() RETURN DISTINCT book"
    )
    q.each do |ret|
      book = ret.book

      covers = book.versions(rel_length: :any).cover.to_a
      if covers.any?
        parent = "#{dir}/book/by/#{fname(book.author)}/#{fname(book.title)}"
        dirname = "#{parent}/covers"

        covers.each.with_index(1) do |cover, idx|
          cover.versions.each do |version|
            begin
              filename = "#{version.isbn}.#{cover.mimetype.split('/').pop.split('+').first}"
            rescue NoMethodError => err
              raise RuntimeError, "Error Parsing Mimetype: #{mimetype} (#{cover.ipfs_id})"
            end
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

        Dir.exists?(parent) && FileUtils.chdir(parent) do
          if !Dir.exists?('.git')
            system('git init')
          end
          system('git', 'add', '.')
          system('git', 'commit', '-m', 'images from isfdb 📷')
        end
      end
    end
  end

  desc 'Export cover images to mfs://covers-{Time.now.iso8601}'
  task(:covers, [:dir] => [:environment]) do |t, args|
    require 'ipfs/client'

    dir = args[:dir] || "/covers-#{Time.now.iso8601}"

    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (book:Book) WHERE (book:Book)-[:CVR]->() OR (book:Book)-->()-[:CVR]->() RETURN DISTINCT book"
    )
    q.each do |ret|
      book = ret.book

      covers = book.versions(rel_length: :any).cover.to_a
      if covers.any?
        parent = "#{dir}/book/by/#{fname(book.author)}/#{fname(book.title)}"
        dirname = "#{parent}/covers"

        covers.each.with_index(1) do |cover, idx|
          cover.versions.each do |version|
            begin
              filename = "#{version.isbn}.#{cover.mimetype.split('/').pop.split('+').first}"
            rescue NoMethodError => err
              raise RuntimeError, "Error Parsing Mimetype: #{mimetype} (#{cover.ipfs_id})"
            end
            fullname = "#{dirname}/#{filename}"
            puts "  Adding: #{fullname} (#{cover.ipfs_id})"
            IPFS::Client.default.files.mkdir(dirname, { parents: true })
            IPFS::Client.default.files.cp(`/ipfs/${cover.ipfs_id}`, fullname)
          end
        end
      end
    end
  end
end