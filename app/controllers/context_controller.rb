class ContextController < ApplicationController
  def index
    @root = root = Context.find_by(name: '∅')
    @path = params[:path]
    @path += ".#{params[:format]}" if params[:format] # couldn't turn this off
    (@path || '').split('/').each.with_index do |p, i|
      @root = (
        @root.subcontexts("c#{i}").where("c#{i}.name = {c#{i}name}")
        .params("c#{i}name": p)
      )
    end

    @contexts = @root.contexts(:r).order('r.name').limit(50)
    @subcontexts = @root.subcontexts(:r).order('r.name').limit(50)

    @books = (
      @root.subcontexts(rel_length: {min:0}).for(:b)
      .distinct
      .order('b.author, b.title')
      .limit(50)
    )
  end
end
