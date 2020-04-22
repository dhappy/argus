class BookController < ApplicationController
  include ActionController::Live
  protect_from_forgery except: :ingest

  def show
    @book = Book.find(params[:uuid])
  end

  def ingest
    begin
      response.headers['Content-Type'] = 'text/event-stream'

      unless params[:filename].present? && params[:book_id].present?
        raise RuntimeError, 'Missing Required Parameter'
      end

      filename = "#{Rails.root}/../.../trainpacks/#{params[:filename]}"
      unless File.exists?(filename)
        raise RuntimeError, "Missing File: #{filename}"
      end

      book = Book.find(params[:book_id])
      unless book.present?
        raise RuntimeError, "Missing Book: #{params[:book_id]}"
      end

      outdir = "#{Rails.root}/../.../book/by/#{helpers.fname(book.author)}/#{helpers.fname(book.title)}/"

      FileUtils.makedirs(outdir)
      FileUtils.copy(filename, outdir)

      FileUtils.chdir(outdir) do

        filename = File.basename(filename)
        ext = File.extname(filename)

        response.stream.write "Created: #{outdir}/#{filename}\n"

        if ext == '.zip'
          response.stream.write "Unzipping: #{filename}\n"
          system('unzip', '-u', filename)
          FileUtils.rm(filename)
        end

        if ext == '.rar'
          response.stream.write "Unrarring: #{filename}\n"
          system('unrar', 'x', '-u', filename)
          FileUtils.rm(filename)
        end

        %w[htm html epub rtf mobi lit txt pdf doc azw3].each do |type|
          files = Dir.glob("*.#{type}")

          if files.length == 1 && !File.exists?("index.#{type}")
            response.stream.write "Creating: index.#{type}\n"
            FileUtils.mv(files.first, "index.#{type}")
          end
        end

        if File.exists?('index.htm') && !File.exists?('index.html')
          FileUtils.mv('index.htm', 'index.html')
        end
      end
    rescue RuntimeError => err
      response.stream.write "#{err.message}\n"
    ensure
      response.stream.close
    end      
  end
end
