namespace :isfdb do
  desc 'Import from the Internet Speculative Fiction Database'

  task(awards: :environment) do |t, args|
    root = Context.merge(name: '∅')
    base = Context.merge(name: :award)
    root.subcontexts << base

    client = Mysql2::Client.new(
      host: 'localhost', database: 'isfdb'
    )
    types = client.query(
      'SELECT DISTINCT' \
      + ' award_type_id AS id,' \
      + ' award_type_short_name AS shortname,' \
      + ' award_type_name AS name' \
      + ' FROM award_types',
      symbolize_keys: true
    )
    types.each do |type|
      puts "Award: #{type[:name]}"

      entries = client.query(
        'SELECT' \
        + ' award_title AS title,' \
        + ' award_author AS author,' \
        + ' award_cat_name AS cat,' \
        + ' award_year AS year' \
        + ' FROM awards' \
        + ' INNER JOIN award_cats' \
        + ' ON awards.award_cat_id = award_cats.award_cat_id' \
        + " WHERE award_type_id = #{type[:id]}",
        symbolize_keys: true,
        cast: false # dates are of form YYYY-00-00
      )
      entries.each do |entry|
        # award/Hugo/1968/Best Novel/winner
        # award/Hugo/1968/Best Novel/nominee/1

        entry[:year].sub!(/-.*/, '')
        paths = [
          [
            {name: type[:name], type: :award},
            {name: entry[:year], type: :year},
            {name: entry[:cat], type: :category}
          ],
          [
            {name: type[:name], type: :award},
            {name: entry[:cat], type: :category},
            {name: entry[:year], type: :year}
          ]
        ]
        paths.each do |path|
          curr = base
          path.each{ |p| curr = curr.subcontexts.find_or_create_by(p) }
          curr.for << Book.merge(author: entry[:author], title: entry[:title])
        end
      end
    end
  end
end