class CreateContext < Neo4j::Migrations::Base
  def up
    add_constraint :Context, :uuid
  end

  def down
    drop_constraint :Context, :uuid
  end
end
