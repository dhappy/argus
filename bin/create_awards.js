#!/usr/bin/env node

import mysql from 'mysql2/promise'
import neo4j from 'neo4j-driver'
import jsdom from 'jsdom'
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
  await setUUIDs('Person')
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

    const LIMIT = Number.MAX_VALUE//5 // return limit for debugging purposes
    let done = false
    let count = 0
    // limit to paginate & avoid overflowing the stack
    const limit = Math.min(LIMIT, 500)
    while(!done) {
      const TYPES = [
        'ANTHOLOGY', 'COLLECTION', 'NOVEL', 'NONFICTION',
        'OMNIBUS', 'POEM', 'SHORTFICTION', 'CHAPBOOK',
      ]
      console.info(`Selecting: ${count * limit}+${limit} from ${award.shortname} (${award.id})`)
      const nomineesQuery = (`
        SELECT
        award_title AS title,
        award_author AS author,
        award_cat_name AS cat,
        award_year AS year,
        award_level AS level
        FROM awards
        LEFT JOIN award_cats ON awards.award_cat_id = award_cats.award_cat_id
        WHERE award_type_id = ?
        AND (award_movie IS NULL OR award_movie = '')
        LIMIT ${limit}
        OFFSET ${count++ * limit}
      `)

      const [raws, fields] = (
        await connection.query(
          nomineesQuery, [award.id],
        )
      )
      
      done = (count * limit > LIMIT || raws.length < limit)

      console.info(` Selected: ${raws.length} from ${award.shortname} (${done}) (Page #${count})`)

      const rows = raws.map((row) => ({
        ...row,
        title: derefEntities(row.title),
        authors: derefEntities(row.author).split('+'),
        cat: optNameArray(row.cat),
      }))
      
      for(
        let {
          title, authors, cat, year, level,
        }
        of
        rows
      ) {
        if(title === 'untitled') {
          console.info(
            `Skipping: ${
              authors.length > 0 ? `${authors.join("'s & ")}'s` : ''
            } Entry in ${cat} ("untitled")`
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
              MERGE (c)-[:PART_OF]->(a)
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
                  MERGE (a:Person:Author {name: $name})
                  ON CREATE SET a.uuid = apoc.create.uuid()
                  RETURN a
                `,
                { name: author },
              )
              return getUUID(result)
            })
          )

          let cypher = (
            creatorUUIDs.map((uuid, i) => (
              `MATCH (p${i}:Person {uuid: "${uuid}"})\n`
            ))
            .join('')
          )
          cypher += (
            `MERGE (w:Work:Book {title: $title})\n`
          )
          cypher += (
            creatorUUIDs.map((uuid, i) => (
              `MERGE (w)-[r${i}:BY]->(p${i})\n`
            ))
            .join('')
          )
          cypher += (
            "ON CREATE SET w.uuid = apoc.create.uuid()\n"
          )
          if(authors.length > 1) {
            cypher += (
              creatorUUIDs.map((uuid, i) => (
                `ON CREATE SET r${i}.rank = ${i + 1}\n`
              ))
              .join('')
            )
          }
          cypher += 'RETURN w'
          result = await neoExec(
            cypher, { title }
          )
          const workUUID = getUUID(result)

          if(!workUUID) {
            console.warn('Failed Query', cypher)
          }

          result = await neoExec(
            `
              MATCH (w:Work {uuid: $workUUID})
              MATCH (y:Year {uuid: $yearUUID})
              MATCH (c:Category {uuid: $catUUID})
              MATCH (a:Award {uuid: $awardUUID})
              WITH w, y, c, a
              WHERE NOT EXISTS {
                MATCH (x)-[:FOR]->(a)
                WHERE (
                  (x)-[:IN]->(y)
                  AND (x)-[:IS]->(w)
                  AND (x)-[:IN]->(c)
                )
              }
              CREATE (n:Nominee${parseInt(level, 10) === 1 ? ':Winner' : ''})
              CREATE (n)-[:IS]->(w)
              CREATE (n)-[:IN]->(y)
              CREATE (n)-[:IN]->(c)
              CREATE (n)-[:FOR]->(a)
              SET n.uuid = apoc.create.uuid()
              SET n.place = $level
              RETURN n
            `,
            { workUUID, yearUUID, catUUID, awardUUID, level },
          )
          const nomineeUUID = getUUID(result)

          console.info(`  Created: (${award.shortname}) ${title}`)
        }
      }
    }
  }))

  console.info("Closing Connection")
  await connection.close()
  await driver.close()
})()
