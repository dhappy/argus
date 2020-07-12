namespace :argus do
  desc 'Insert images into IPFS'
  task(images: :environment) do |t, args|
    require 'net/http'
    require 'ipfs/client'

    q = Cover.as(:c).where(
      'c.cid IS NULL AND c.url IS NOT NULL'
    )
    q.each do |c|
      print "Processing #{c.url}"
      next unless c.url.present?
      res = Net::HTTP.get(URI.parse(c.url.split('|').first))
      Tempfile.open(
        'cover', "#{Rails.root}/tmp", encoding: 'ascii-8bit'
      ) do |file|
        file.write(res)
        #cover = IPFS::Client.default.add(file.path)
        IO.popen(['ipfs', 'add', file.path], 'r+') do |cmd|
          out = cmd.readlines.last
          cid = out&.split.try(:[], 1)
          unless $?.success? && cid
            puts "Error: IPFS Import of #{glob.first})"
            next
          else
            ext = c.url.split('.').pop
            ext = :jpeg if ext == 'jpg'
            c.update({
              mimetype: "image/#{ext}", cid: cid,
            })
          end
        end
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