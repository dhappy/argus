namespace :epubs do
  desc 'Spider [dir] & create epubs where needed'
  task(:create, [:dir] => [:environment]) do |t, args|
    erb = ->(template, out) {
      content = nil
      File.open(template, 'r') { |f| content = f.read }
      result = ERB.new(content, nil, '>').result(binding)
      File.open(out, 'w') { |f| f.write(result) }
    }

    create = ->(dir) {
      template = "#{Rails.root}/epub_template"
      parts = dir.split('/')
      @author = parts[-2]
      @title = parts[-1]
      puts "#{@title}, by #{@author}"
      FileUtils.chdir(dir) do
        %w[META-INF titlepage.xhtml].each do |filename|
          if File.exists?(filename)
            puts "  Skipping: #{filename}"
          else
            FileUtils.cp_r("#{template}/#{filename}", './')
          end
        end
        %w[content.opf toc.ncx cover.svg].each do |filename|
          if File.exists?(filename)
            puts "  Skipping: #{filename}"
          else
            erb.call("#{template}/#{filename}.erb", filename)
          end
        end
        system('zip', 'index.epub', '.', '-r9', '--exclude=.git/*')
      end
    }

    spider = ->(dir) {
      puts dir
      Dir.glob("#{dir}/*").each do |sub|
        if File.directory?(sub)
          spider.call(sub)
        elsif /\/index.html$/.match?(sub)
          next if Dir.glob("#{dir}/index.epub").any?
          create.call(dir)
        end
      end
    }

    dir = args[:dir] || '../.../book'
    spider.call(dir)
  end

  desc 'Read [dir]/#{author}/#{title} & add to git where needed'
  task(:git, [:dir] => [:environment]) do |t, args|
    dir = args[:dir] || '../.../book/by'
    Dir.glob("#{dir}/*/*").each do |sub|
      author, title = *sub.split('/').slice(-2, 2)
      book = Book.find_by(author: author, title: title)
      if book
        puts "Adding: #{title}, by #{author}"

        if book.repo
          puts "  Repo Cached: #{book.repo.ipfs_id}"
        else
          FileUtils.chdir(sub) do
            if Dir.glob('index.epub').any? && Dir.glob('.git').none?
              puts "  Creating Git Structure"
              system('git', 'init')
              system('unzip', '-n', 'index.epub')
              File.open('.gitignore', 'w') { |f| f.write("index.epub\n") }
              system('chmod', '-R', 'a+r', '.') #sometimes has no permissions
              system('git', 'add', '.')
              system('git', 'commit', '-m', 'argus initial import 🦚')
            end

            if Dir.glob('.git').any?
              print "  Caching IPLD CID: "
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
        end
      end
    end
  end
end