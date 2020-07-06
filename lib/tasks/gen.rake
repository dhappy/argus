namespace :gen do
  # This is used to create the author portion of the canonical
  # url because name is open to collisions.
  #
  # Currently just inserts random unique data for each author
  # into the database.
  desc 'Distributed Identifiers for Authors'
  task(dids: :environment) do
    byebug
    Creators.each do |creator|
      unless creator.did
        creator.update(did: "did:key:")
      end
    end
  end
end