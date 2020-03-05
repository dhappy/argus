namespace :isfdb do
  desc 'Import from the Internet Speculative Fiction Database'

  task(awards: :environment) do |t, args|
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
      award = Award.merge(
        name: type[:name],
        shortname: type[:shortname]
      )
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
        puts "#{entry[:cat]}: #{entry[:title]} by #{entry[:author]}"
        Entry.find_or_create_by!(
          award: award,
          year: Year.find_or_create_by!(
            number: entry[:year].sub(/-.*/, '')
          ),
          category: Category.find_or_create_by!(
            name: entry[:cat]
          ),
          won: true,
          nominee: Book.for(entry[:author], entry[:title])
        )
      end
    end
  end
end