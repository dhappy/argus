namespace :export do
  desc 'Export award winners to IPFS'
  task(mfs: :environment) do |t, args|
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

  desc 'Export awards context tree to CBOR-DAG'
  task(awards: :environment) do |t, args|
    root = 'QmUNLLsPACCz1vLxQVkXqqLX5R1X345qqfHbsf67hvA3Nn'

    procCreators = ->(creators) {{
      name: creators.name, legalname: creators.legalname, 
      names: creators.names, aliases: JSON.parse(creators.aliases),
    }}

    procBook = ->(book, pre) {
      obj = {}
      name = "#{pre ? "#{pre}: " : ''}#{book.to_s}"
      obj[name] = {
        creators: procCreators.call(book.creators), title: book.title, uuid: book.uuid,
      }
      obj
    }

    procCat = ->(category) {
      nominees = {}
      results = category.nominees.each_rel.map{ |n| n.result }
      category.nominees.each_with_rel do |book, nom|
        procBook.call(book, nom.result).each do |name, obj|
          nominees[name] = obj
        end
      end
      nominees
    }

    procYear = ->(year) {
      year.categories.reduce({}){ |obj, c| obj[c.title] = procCat.call(c); obj }
    }

    # 'shortname'/'uuid' and title could collide: unlikely
    # links = Award.as(:a).where("a.title = 'Hugo Award' OR a.title = 'Nebula Award'").reduce({}) do |obj, award|
    links = Award.all.reduce({}) do |obj, award|
                            # complicates deserialization
      obj[award.title] = {} # shortname: award.shortname }
      award.years.reduce(obj[award.title]){ |obj, y| obj[y.number] = procYear.call(y); obj }
      obj
    end

    cid = nil
    IO.popen(['ipfs', 'dag', 'put', '--pin'], 'r+') do |cmd|
      cmd.puts JSON.generate(links)
      cmd.close_write
      cid = cmd.readlines.last
      puts "cid:#{cid}"
      unless $?.success? && cid
        puts "Error: IPFS DAG PUT"
        next
      end
    end
  end

  desc 'Export awards context tree to UnixFS Protobuf'
  task(awardsfs: :environment) do |t, args|
    root = 'QmUNLLsPACCz1vLxQVkXqqLX5R1X345qqfHbsf67hvA3Nn'

    procCreators = ->(creators) {{
      name: creators.name, legalname: creators.legalname, 
      names: creators.names, aliases: JSON.parse(creators.aliases),
    }}

    procBook = ->(book, path) {
      obj = {}
      name = book.to_s
      bookCID = book.repo || 'QmVPqdGVWEN7G4KnpDXRsQeNqZehy5AXjbStNokAcPbSBj'
      puts "#{path} #{name}"
      IO.popen(['ipfs', 'object', 'patch', 'add-link', '-p', root, "#{path} #{name}", bookCID], 'r+') do |cmd|
        root = cmd.readlines.last.chomp
        puts "cid:#{root}"
        puts "Error: IPFS OBJ PATCH" unless $?.success?
      end
      bookCID
    }

    procCat = ->(category, path) {
      nominees = {}
      results = category.nominees.each_rel.map{ |n| n.result }
      if results.size == results.compact.uniq.size # there's a complete set of keys
        category.nominees.each_with_rel do |book, nom|
          nominees[nom.result] = procBook.call(book, "#{path}/#{nom.result}:")
        end
      else
        category.nominees.each.with_index(1){ |b, i| nominees[i] = procBook.call(b, "#{path}/#{i}:") }
      end
      nominees
    }

    procYear = ->(year, path) {
      year.categories.reduce({}){ |obj, c| obj[c.title] = procCat.call(c, "#{path}/#{fname(c.title)}"); obj }
    }

    # 'shortname'/'uuid' and title could collide: unlikely
    links = Award.all.reduce({}) do |obj, award|
      obj[award.title] = { shortname: award.shortname }
      award.years.reduce(obj[award.title]){ |obj, y| obj[y.number] = procYear.call(y, "#{fname(award.title)}/#{y.number}"); obj }
      obj
    end

    cid = nil
    IO.popen(['ipfs', 'dag', 'put', '--pin'], 'r+') do |cmd|
      cmd.puts JSON.generate(links)
      cmd.close_write
      cid = cmd.readlines.last
      puts "cid:#{cid}"
      unless $?.success? && cid
        puts "Error: IPFS DAG PUT"
        next
      end
    end
  end

  def fname(str)
    str = str.gsub('%', '%25').gsub('/', '%2F').gsub("\x00", '%00')
    #str.mb_chars.limit(254).to_s # this causes compatability issues
  end

  desc 'Export cover images to [dir] in book/by/#{author}/#{title}/covers/#{isbn}.#{ext}'
  task(:coverimgs, [:dir] => [:environment]) do |t, args|
    require 'ipfs/client'

    dir = args[:dir] || '../...'

    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (book:Book) WHERE (book:Book)-->()-[:CVR]->() RETURN DISTINCT book"
    )
    q.each do |ret|
      book = ret.book

      covers = book.versions(rel_length: :any).cover.to_a
      if covers.any?
        parent = "#{dir}/book/by/#{fname(book.creators.name)}/#{fname(book.title)}"
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
              puts "  Skipping: #{fullname} (#{cover.cid})"
            else
              puts "  Adding: #{fullname} (#{cover.cid})"
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
        parent = "#{dir}/book/by/#{fname(book.creators.name)}/#{fname(book.title)}"
        dirname = "#{parent}/covers"

        covers.each.with_index(1) do |cover, idx|
          cover.versions.each do |version|
            begin
              filename = "#{version.isbn}.#{cover.mimetype.split('/').pop.split('+').first}"
            rescue NoMethodError => err
              raise RuntimeError, "Error Parsing Mimetype: #{mimetype} (#{cover.ipfs_id})"
            end
            fullname = "#{dirname}/#{filename}"
            puts "  Adding: #{fullname} (#{cover.cid})"
            # IPFS::Client.default.files.mkdir(dirname, { parents: true })
            # IPFS::Client.default.files.cp(`/ipfs/${cover.cid}`, fullname)
            system('ipfs', 'files', 'mkdir', '-p', "#{dirname}")
            system('ipfs', 'files', 'cp', "/ipfs/#{cover.cid}", "#{fullname}")
          end
        end
      end
    end
  end
end