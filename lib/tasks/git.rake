namespace :git do
  desc 'Spider [dir], find git repositories, & run a git command: [cmd]'
  task(:cmd, [:cmd, :dir] => [:environment]) do |t, args|
    cmd = args[:cmd].split(' ')

    run = ->(dir) {
      puts "Running git #{cmd.join(' ')} in #{dir}"
      FileUtils.chdir(dir) do
        system(*(%w[git] + cmd))
      end
    }

    spider = ->(dir) {
      Dir.glob("#{dir}/*").each do |sub|
        if File.directory?(sub)
          isGit = /\/.git$/.match?(sub)
          puts "Check #{sub} #{isGit}"
          isGit ? run.call(dir) : spider.call(sub)
        end
      end
    }

    dir = args[:dir] || '../.../book'
    spider.call(dir)
  end

  desc 'Git add all, commit [dir]/#{author}/#{title}, caching the IPFS CID'
  task(:commit, [:msg, :dir] => [:environment]) do |t, args|
    raise RuntimeError, 'Usage: rake git:commit[commit message]' unless args[:msg].present?

    dir = args[:dir] || '../.../book/by'

    erb = ->(template, out) {
      content = nil
      File.open(template, 'r') { |f| content = f.read }
      result = ERB.new(content, nil, '>').result(binding)
      File.open(out, 'w') { |f| f.write(result) }
    }

    create = ->(book) {
      template = "#{Rails.root}/epub_template"
      parts = dir.split('/')
      @author = book.author
      @title = book.title
      puts "#{@title}, by #{@author}"

      %w[META-INF titlepage.xhtml].each do |filename|
        if File.exists?(filename)
          puts "  Skipping: #{filename}"
        else
          FileUtils.cp_r("#{template}/#{filename}", './')
        end
      end
      %w[content.opf toc.ncx].each do |filename|
        if File.exists?(filename)
          puts "  Skipping: #{filename}"
        else
          erb.call("#{template}/#{filename}.erb", filename)
        end
      end
      if (Dir.glob('cover*') + Dir.glob('covers/*')).any?
        puts "  Skipping: cover.svg"
      else
        erb.call("#{template}/cover.svg.erb", 'cover.svg')
      end

      system('zip', 'index.epub', '.', '-r9', '--exclude=.git/*')
    }

    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (c:Context)-[:SUB*]->()-[:FOR]->(book:Book) WHERE c.type='award' AND c.name = 'Hugo Award' RETURN DISTINCT book"
    )
    missing = 0
    found = 0
    q.each do |ret|
      book = ret.book

      fulldir = "#{dir}/#{fname(book.author)}/#{fname(book.title)}"

      unless Dir.exists?(fulldir)
        missing += 1
        puts "Missing: (#{missing}/#{missing + found}) #{fulldir}"
      else
        found += 1
        puts "Checking: (#{found}/#{missing + found}) #{fulldir}"
        FileUtils.chdir(fulldir) do
          next if Dir.glob(?*).size == 0

          if !Dir.exists?('.git')
            system('git', 'init')
          end

          unless File.exists?('.gitignore')
            File.open('.gitignore', 'w') { |f| f.write("index.epub\n") }
          end

          if File.exists?('index.epub')
            unless Dir.exists?('META-INF')
              system('unzip', '-n', 'index.epub')
            end
          else
            if File.exists?('index.html')
              create.call(book)
            end
          end

          if Dir.glob('*html').any? && (Dir.glob('cover*') + Dir.glob('covers/*')).empty?
            create.call(book)
          end

          system('git', 'add', '.')
          system('git', 'commit', '-m', args[:msg])

          print "  #{Time.now}: Caching IPFS CID: "
          IO.popen(['git', 'push', 'ipfs::', 'master'], err: [:child, :out]) do |io|
            lines = io.readlines
            line = lines.find{ |l| /^Pushed to IPFS as /.match?(l) }
            unless line
              puts "No CID: Error On Import?"
            else
              cid = line.match(/\.*ipfs:\/\/(.*)\e.*/)[1]
              puts cid
              if book.repo&.ipfs_id != cid
                system('ipfs', 'pin', 'add', '-r', cid)
                book.repo = Content.find_or_create_by(ipfs_id: cid)
              end
            end
          end
        end
      end
    end
  end
end