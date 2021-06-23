#!/usr/bin/env node

import mysql from 'mysql2/promise'
import neo4j from 'neo4j-driver'
import jsdom from 'jsdom'
import { of } from 'rxjs'
const { JSDOM } = jsdom

const derefEntities = (str) => {
  const dom = new JSDOM(str)
  return dom.window.document.firstChild.textContent
}

const optNameArray = (raw, splitOn = /\s+\/\s+/) => {
  const names = derefEntities(raw).split(splitOn)
  return (names.length <= 1) ? names[0] : names
}

const driver = (
  neo4j.driver(
    'bolt://localhost',
    neo4j.auth.basic('neo4j', 'neo'),
  )
)
const neoExec = async (cmd, args) => {
  let session = driver.session()
  try {
    return await session.run(cmd, args)
  } finally {
    await session.close()
  }
}

const setUUIDs = async (label) => {
  await neoExec(`
    CREATE CONSTRAINT IF NOT EXISTS ON (a:${label})
    ASSERT a.uuid IS UNIQUE
  `)
  await neoExec(`
    CALL apoc.uuid.install("${label}", { addToExistingNodes: true })
  `)
}

;(async () => {
  const connection = (
    await mysql.createConnection({
      host: 'localhost',
      user: 'will',
      password: '',
      database: 'isfdb',
    })
  )
  // connection.connect((err) => {
  //   if(err) throw err
  //   console.log('Connected!')
  // })
  const awardsQuery = (`
    SELECT DISTINCT
    award_type_id AS id,
    award_type_short_name AS shortname,
    award_type_name AS name
    FROM award_types
  `)
  const [raws, fields] = (
    await connection.query(awardsQuery)
  )
  const rows = raws.map((row) => ({
    id: row.id,
    name: optNameArray(row.name),
    shortname: optNameArray(row.shortname),
  }))

  await setUUIDs('Award')
  await setUUIDs('Category')
  await setUUIDs('Year')
  await setUUIDs('Book')
  await setUUIDs('Author')
  await setUUIDs('Nominee')
  await setUUIDs('Edition')
  await setUUIDs('Publisher')
  await setUUIDs('eBook')
  
  await Promise.all(rows.map(async (award) => {
    const result = await neoExec(
      `
        MERGE (a:Award {name: $name, shortname: $shortname})
        ON CREATE SET a.uuid = apoc.create.uuid()
        RETURN a
      `,
      award,
    )
    const awardNode = result.records[0].get(0)

    const nomineesQuery = (`
      SELECT
      award_title AS title,
      award_author AS author,
      award_cat_name AS cat,
      award_year AS year,
      award_movie AS movie,
      title_id AS tid,
      title_parent AS parent,
      title_ttype AS ttype,
      title_copyright AS cpdate,
      award_level AS level
      FROM awards
      INNER JOIN award_cats ON awards.award_cat_id = award_cats.award_cat_id
      INNER JOIN titles ON title_title = award_title
      WHERE award_type_id = ?
      AND title_ttype IN (?)
      LIMIT 3
    `)
    const TTYPES = [
      'ANTHOLOGY', 'COLLECTION', 'NOVEL', 'NONFICTION',
      'OMNIBUS', 'POEM', 'SHORTFICTION', 'CHAPBOOK',
    ]

    const [raws, fields] = (
      await connection.query(
        nomineesQuery, [award.id, TTYPES],
      )
    )
    const rows = raws.map((row) => ({
      ...row,
      title: derefEntities(row.title),
      authors: derefEntities(row.author).split('+'),
      cat: optNameArray(row.cat),
    }))
    
    for(
      const {
        title, author, authors, cat, year, movie,
        tid, parent, ttype, cpdate, level,
      }
      of
      rows
    ) {
      if(title === 'untitled') {
        console.info(`Skipping ${authors.join("'s & ")}'s Entry in ${cat} ("untitled")`)
      } else {
        console.info(`Processing: ${title} by ${authors.join(' & ')}`)

        let result = await neoExec(
          `
            MERGE (c:Category {name: $name})
            ON CREATE SET c.uuid = apoc.create.uuid()
            RETURN c
          `,
          { name: cat },
        )
        const catNode = result.records[0].get(0)
    
        result = await neoExec(
          `
            MATCH (c:Category {uuid: $catUUID})
            MATCH (a:Award {uuid: $awardUUID})
            MERGE (c)-[:OF]->(a)
          `,
          {
            catUUID: catNode.properties.uuid,
            awardUUID: awardNode.properties.uuid,
          },
        )

        result = await neoExec(
          `
            MERGE (y:Year {number: $number})
            ON CREATE SET y.uuid = apoc.create.uuid()
            RETURN y
          `,
          { number: year.getFullYear() },
        )
        const yearNode = result.records[0].get(0)

        const authorNodes = await Promise.all(
          authors.map(async (author) => {
            const result = await neoExec(
              `
                MERGE (a:Author {name: $name})
                ON CREATE SET a.uuid = apoc.create.uuid()
                RETURN a
              `,
              { name: author },
            )
            return result.records[0].get(0)
          })
        )

        let cypher = (
          authorNodes.map((n, i) => (
            `MATCH (a${i}:Author {uuid: "${n.properties.uuid}"})\n`
          ))
          .join('')
        )
        cypher += "MERGE (b:Book {title: $title})\n"
        cypher += (
          authorNodes.map((n, i) => (
            `MERGE (b)-[r${i}:BY]->(a${i})\n`
          ))
          .join('')
        )
        cypher += "ON CREATE SET b.uuid = apoc.create.uuid()\n"
        if(authors.length > 1) {
          cypher += (
            authorNodes.map((n, i) => (
              `SET r${i}.rank = ${i + 1}\n`
            ))
            .join('')
          )
        }
        cypher += 'RETURN b'
        result = await neoExec(cypher, { title })
        const bookNode = result.records[0].get(0)

        result = await neoExec(
          `
            MATCH (b:Book {uuid: $bookUUID})
            MATCH (y:Year {uuid: $yearUUID})
            MATCH (c:Category {uuid: $catUUID})
            MATCH (a:Award {uuid: $awardUUID})
            MERGE (n:Nominee)
            MERGE (n)-[:IS]->(b)
            MERGE (n)-[:IN]->(y)
            MERGE (n)-[:OF]->(c)
            MERGE (n)-[:FOR]->(a)
            ON CREATE SET n.uuid = apoc.create.uuid()
            RETURN n
          `,
          {
            bookUUID: bookNode.properties.uuid,
            yearUUID: yearNode.properties.uuid,
            catUUID: catNode.properties.uuid,
            awardUUID: awardNode.properties.uuid,
          },
        )
        const nomineeNode = result.records[0].get(0)


        console.info(`  Creating: ${title}`)
      }
    }

  
    //console.log(node.properties.name)
  }))

  await connection.close()
  await driver.close()
})()
