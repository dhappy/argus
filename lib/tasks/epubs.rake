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
        system('zip', 'index.epub', '.', '-r')
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
end