class PagesController < ApplicationController
  def review
    count = params[:count] ? params[:count].to_i : 50
    skip = params[:skip].to_i
    q = Neo4j::ActiveBase.current_session.query(
      "MATCH (book:Book) WHERE NOT (book)-[:DAT]->() RETURN DISTINCT book SKIP #{skip} LIMIT #{count}"
    )
    @books = {}
    q.each do |ret|
      book = ret.book
      existing = Dir.glob(
        "#{Rails.root}/../book/by/#{helpers.fname(book.author)}/#{helpers.fname(book.title)}/index.*"
      )

      FileUtils.chdir("#{Rails.root}/../.../trainpacks/") do
        possibilities = Dir.glob("*#{book.author}*#{book.title}*")
        possibilities += Dir.glob("*#{book.title}*#{book.author}*")
        if(possibilities.any?)
          @books[book.uuid] = OpenStruct.new(
            book: book, existing: existing, possibilities: possibilities
          )
        end
      end
    end
  end
end