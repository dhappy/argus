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

const getUUID = (result) => (
  result.records[0]?.get(0)?.properties.uuid
)

const capitalize = (str) => (
  str.split(/\s+/g)
  .map((sub) => (`${
    sub?.[0]?.toUpperCase() ?? ''
  }${
    sub?.substring(1)?.toLowerCase() ?? ''
  }`))
  .join(' ')
)

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
  await setUUIDs('Work')
  await setUUIDs('Creator')
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
    const awardUUID = getUUID(result)

    const LIMIT = null //1 // return limit for debugging purposes
    let done = false
    let count = 0
    // limit to paginate & avoid overflowing the stack
    const limit = Math.min(LIMIT ?? Number.MAX_VALUE, 500)
    while(!done) {
      const TYPES = [
        'ANTHOLOGY', 'COLLECTION', 'NOVEL', 'NONFICTION',
        'OMNIBUS', 'POEM', 'SHORTFICTION', 'CHAPBOOK',
      ]
      const nomineesQuery = (`
        SELECT
        award_title AS title,
        award_author AS author,
        award_cat_name AS cat,
        award_year AS year,
        award_movie AS movie,
        title_id AS tid,
        title_parent AS parent,
        title_ttype AS type,
        title_copyright AS copyright,
        award_level AS level
        FROM awards
        INNER JOIN award_cats ON awards.award_cat_id = award_cats.award_cat_id
        INNER JOIN titles ON title_title = award_title
        WHERE award_type_id = ?
        AND title_ttype IN (?)
        AND award_title != 'untitled' -- people awards, not books
        LIMIT ${limit}
        OFFSET ${count++ * limit}
      `)

      const [raws, fields] = (
        await connection.query(
          nomineesQuery, [award.id, TYPES],
        )
      )
      
      done = (count * limit > LIMIT || raws.length === 0)

      const rows = raws.map((row) => ({
        ...row,
        title: derefEntities(row.title),
        authors: derefEntities(row.author).split('+'),
        cat: optNameArray(row.cat),
      }))
      
      for(
        let {
          title, authors, cat, year, movie,
          tid, parent, type, copyright, level,
        }
        of
        rows
      ) {
        if(title === 'untitled') {
          console.info(
            `Skipping ${authors.length > 0 ? `${authors.join("'s & ")}'s` : ''}${
            ' '}Entry in ${cat} ("untitled")`
          )
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
          const catUUID = getUUID(result)
      
          result = await neoExec(
            `
              MATCH (c:Category {uuid: $catUUID})
              MATCH (a:Award {uuid: $awardUUID})
              MERGE (c)-[:OF]->(a)
            `,
            { catUUID, awardUUID },
          )

          result = await neoExec(
            `
              MERGE (y:Year {number: $number})
              ON CREATE SET y.uuid = apoc.create.uuid()
              RETURN y
            `,
            { number: year.getFullYear() },
          )
          const yearUUID = getUUID(result)

          const creatorUUIDs = await Promise.all(
            authors.map(async (author) => {
              const result = await neoExec(
                `
                  MERGE (a:Creator:${movie ? 'Director' : 'Author'} {name: $name})
                  ON CREATE SET a.uuid = apoc.create.uuid()
                  RETURN a
                `,
                { name: author },
              )
              return getUUID(result)
            })
          )

          if(type === 'SHORTFICTION') {
            type = 'Short Fiction'
          }
          type = capitalize(type)

          copyright = copyright?.toISOString?.()

          let cypher = (
            creatorUUIDs.map((uuid, i) => (
              `MATCH (c${i}:Creator {uuid: "${uuid}"})\n`
            ))
            .join('')
          )
          cypher += (
            `MERGE (w:Work:${movie ? 'Movie' : 'Book'} {title: $title})\n`
          )
          cypher += (
            creatorUUIDs.map((uuid, i) => (
              `MERGE (w)-[r${i}:BY]->(a${i})\n`
            ))
            .join('')
          )
          cypher += (
            `ON CREATE SET w.uuid = apoc.create.uuid(), w.type = $type\n`
          )
          if(authors.length > 1) {
            cypher += (
              creatorUUIDs.map((uuid, i) => (
                `ON CREATE SET r${i}.rank = ${i + 1}\n`
              ))
              .join('')
            )
          }
          cypher += (
            `ON CREATE SET w.copyright = $copyright\n`
          )
          cypher += 'RETURN w'
          result = await neoExec(
            cypher, { title, type, copyright }
          )
          const workUUID = getUUID(result)

          result = await neoExec(
            `
              MATCH (w:Work {uuid: $workUUID})
              MATCH (y:Year {uuid: $yearUUID})
              MATCH (c:Category {uuid: $catUUID})
              MATCH (a:Award {uuid: $awardUUID})
              WHERE NOT EXISTS((a)<-[:FOR]-()-[:IN]->(y))
              CREATE (n:Nominee${level === '1' ? ':Winner' : ''})
              CREATE (n)-[:IS]->(w)
              CREATE (n)-[:IN]->(y)
              CREATE (n)-[:OF]->(c)
              CREATE (n)-[:FOR]->(a)
              SET n.uuid = apoc.create.uuid()
              RETURN n
            `,
            { workUUID, yearUUID, catUUID, awardUUID },
          )
          const nomineeUUID = getUUID(result)

          console.info(`  Created: (${award.shortname}) ${title}`)
        }
      }
    }
  
    //console.log(node.properties.name)
  }))

  await connection.close()
  await driver.close()
})()
