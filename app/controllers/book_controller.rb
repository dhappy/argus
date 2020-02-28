class BookController < ApplicationController
  def show
    @book = Book.find(params[:uuid])
  end
end
