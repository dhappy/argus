class BookController < ApplicationController
  def show
    @book = Book.find(params[:uuid])
  end

  def ingest
    if params[:filename].nil? || params[:book_id].nil?
      respond_with 'Missing Required Parameter', status: 503
    end

    filename = 

    respond_with nil
  end
end
