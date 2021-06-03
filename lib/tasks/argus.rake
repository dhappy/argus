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
    q = Neo4j::ActiveBase.current_session.query(
      'MATCH (creators:Creators)-->(book:Book)' \
      + ' MERGE (:Root)-[:CHILD {name: "book"}]->' \
      + ' (:Position)-[:CHILD {name: "by"}]->' \
      + ' (:Position)-[:CHILD {name: creators.name}]->' \
      + ' (pc:Position)-[:CHILD {name: book.title}]->' \
      + ' (pb:Position),' \
      + ' (pc)-[:EQUALS]->(creators),' \
      + ' (pb)-[:EQUALS]->(book)' \
      + ' LIMIT 10'
    )
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