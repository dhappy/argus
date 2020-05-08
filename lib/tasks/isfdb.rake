desc 'Import from the Internet Speculative Fiction Database'
namespace :isfdb do
  desc 'Import award winners and nominees'
  task(awards: :environment) do |t, args|
    LEVELS = {
      '71': 'No Winner -- Insufficient Votes',
      '72': 'Not on ballot -- Insufficient Nominations',
      '73': 'No Award Given This Year',
      '81': 'Withdrawn',
      '82': 'Withdrawn -- Nomination Declined',
      '83': 'Withdrawn -- Conflict of Interest',
      '84': 'Withdrawn -- Official Publication in a Previous Year',
      '85': 'Withdrawn -- Ineligible',
      '90': 'Finalists',
      '91': 'Made First Ballot',
      '92': "Preliminary Nominees",
      '93': 'Honorable Mentions',
      '98': 'Early Submissions',
      '99': 'Nominations Below Cutoff',
    }

    client = Mysql2::Client.new(
      host: 'localhost', database: 'isfdb'
    )
    types = client.query(
      (
        'SELECT DISTINCT' \
        + ' award_type_id AS id,' \
        + ' award_type_short_name AS shortname,' \
        + ' award_type_name AS name' \
        + ' FROM award_types' \
        # + ' WHERE award_type_name = "Hugo Award"' \
      ),
      symbolize_keys: true
    )
    types.each do |type|
      award = Award.merge(
        title: Nokogiri::HTML.parse(type[:name]).text,
        shortname: Nokogiri::HTML.parse(type[:shortname]).text,
      )
      puts "Award: #{award.shortname}"

      entries = client.query(
        (
          'SELECT' \
          + ' award_title AS title,' \
          + ' award_author AS author,' \
          + ' award_cat_name AS cat,' \
          + ' award_year AS year,' \
          + ' award_movie AS movie,' \
          + ' title_ttype AS ttype,' \
          + ' title_copyright AS cpdate,' \
          + ' award_level as level' \
          + ' FROM awards' \
          + ' INNER JOIN award_cats' \
          + ' ON awards.award_cat_id = award_cats.award_cat_id' \
          + ' INNER JOIN titles' \
          + ' ON title_title = award_title' \
          + " WHERE award_type_id = #{type[:id]}" \
          + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
        ),
        symbolize_keys: true,
        cast: false # dates are of form YYYY-00-00
      )
      entries.each do |entry|
        title = Nokogiri::HTML.parse(entry[:title]).text
        next if title == 'untitled' # an artist or editor award
        entry[:year].sub!(/-.*/, '')
        year = award.years.find_or_create_by(
          number: entry[:year]
        )
        category = year.categories.find_or_create_by(
          title: Nokogiri::HTML.parse(entry[:cat]).text
        )
        author = Nokogiri::HTML.parse(entry[:author]).text
        author, pseudo = author.split('^') if author.include?('^')
        authors = author.split('+').join(' & ') # unique: true doesn't work w/ an array

        art = (
          if entry[:movie].present?
            Movie.find_or_create_by(by: authors, title: title)
          else
            Book.find_or_create_by(authors: authors, title: title)
            .tap do |book|
              book.alias = pseudo
              book.copyright ||= entry[:cpdate]
              book.types = '[]' unless book.types
              book.types = (JSON.parse(book.types)).push(entry[:ttype]).uniq
              book.save
            end
          end
        )

        unless art.nominations.include?(category)
          puts "Linking: #{award.title}: #{year.number}: #{art}"
          Nomination.create(
            from_node: category, to_node: art, result: entry[:level]
          )
        end
      end
    end
  end

  desc 'Import information about series'
  task(series: :environment) do |t, args|
    root = Context.merge(name: '∅')
    base = (
      root.subcontexts.find_or_create_by(name: :book)
      .subcontexts.find_or_create_by(name: :by)
    )
    client = Mysql2::Client.new(
      host: 'localhost', database: 'isfdb'
    )
    pubs = client.query( # where series_parent is null
      (
        'SELECT DISTINCT' \
        + ' series_title AS series,' \
        + ' title_title AS title,' \
        + ' title_ttype AS ttype,' \
        + ' title_copyright AS cpdate,' \
        + ' title_seriesnum as snum,' \
        + ' title_seriesnum_2 as snum2,' \
        + ' author_canonical AS author' \
        + ' FROM series, titles, canonical_author, authors' \
        + ' WHERE titles.series_id=series.series_id' \
        + ' AND titles.title_id=canonical_author.title_id' \
        + ' AND canonical_author.author_id=authors.author_id' \
        + ' AND series_parent IS NULL' \
        + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
      ),
      symbolize_keys: true
    )
    pubs.each do |pub|
      title = Nokogiri::HTML.parse(entry[:title]).text
      next if title == 'untitled' # an artist or editor award
      author = Nokogiri::HTML.parse(entry[:author]).text
      author, pseudo = author.split('^') if author.include?('^')
      authors = author.split('+').join(' & ')
      book = Book.find_or_create_by(authors: authors, title: title)
      art = (
        if entry[:movie].present?
          Movie.find_or_create_by(by: authors, title: title)
        else
          Book.find_or_create_by(authors: authors, title: title)
          .tap do |book|
            book.alias = pseudo
            book.copyright ||= entry[:cpdate]
            book.types = [] unless book.types
            book.types = (JSON.parse(book.types)).push(entry[:ttype]).uniq
            book.save
          end
        end
      )
      series = Series.find_or_create_by(
        title: Nokogiri::HTML.parse(entry[:series]).text
      )
      unless art.series.include?(series)
        puts "Linking: #{series.title}: #{book.copyright}: #{art}"
        Contains.create(
          from_node: series, to_node: art,
          rank: "#{entry[:snum]}#{entry[:snum] ? '.' + entry[:snum] : ''}",
        )
      end
    end
  end

  desc 'Import information about cover images and isbns'
  task(covers: :environment) do |t, args|
    root = Context.merge(name: '∅')
    base = (
      root.subcontexts.find_or_create_by(name: :book)
      .subcontexts.find_or_create_by(name: :by)
    )
    client = Mysql2::Client.new(
      host: 'localhost', database: 'isfdb'
    )
    pubs = client.query(
      'SELECT DISTINCT' \
      + ' pub_title AS title,' \
      + ' author_canonical AS author,' \
      + ' pub_isbn AS isbn,' \
      + ' pub_frontimage AS image' \
      + ' FROM pubs' \
      + ' JOIN pub_authors ON pubs.pub_id = pub_authors.pub_id' \
      + ' JOIN authors ON pub_authors.author_id = authors.author_id',
      symbolize_keys: true
    )
    pubs.each do |pub|
      book = Book.merge(author: pub[:author], title: pub[:title])
      if pub[:isbn].present?
        version = book.versions.find_or_create_by(isbn: pub[:isbn])
        if pub[:image].present?
          version.cover = Content.find_or_create_by(url: pub[:image])
        end
      end

      paths = [
        [
          {name: pub[:author], type: :author},
          {name: pub[:title], type: :title}
        ]
      ]
      paths.each do |path|
        puts "book/by/#{path.map{|p| p[:name]}.join('/')}"
        curr = base
        path.each{ |p| curr = curr.subcontexts.find_or_create_by(p) }
        curr.for << book
      end
    end
  end
end