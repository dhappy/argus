require "#{Rails.root}/app/helpers/application_helper"
include ApplicationHelper

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
    Dir.glob("#{dir}/*/*").each.with_index(1) do |sub, idx|
      author, title = *sub.split('/').slice(-2, 2)
      book = Book.find_by(author: author, title: title)
      if book
        puts "#{Time.now}: (#{ActionController::Base.helpers.number_with_delimiter(idx)}) Adding: #{title}, by #{author}"

        FileUtils.chdir(sub) do
          unless Dir.exists?('.git')
            system('git', 'init')
          end

          if File.exists?('index.epub')
            unless Dir.exists?('META-INF')
              system('unzip', '-n', 'index.epub')
            end

            unless File.exists?('.gitignore')
              File.open('.gitignore', 'w') { |f| f.write("index.epub\n") }
            end
          end


          system('chmod', '-R', 'a+r', '.') # some files have no permissions


          if Dir.glob('.git').any?
            system('git', 'add', '.')
            system('git', 'commit', '-m', 'argus initial import 🦚')

            print "  Caching IPFS CID: "
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
end