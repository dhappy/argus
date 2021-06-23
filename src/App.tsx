import { Button } from '@chakra-ui/react'
import neo4j from 'neo4j-driver'
import { useEffect, useMemo } from 'react'

// eslint-disable-next-line import/no-anonymous-default-export
export default () => {
  const driver = useMemo(() => (
    neo4j.driver(
      'bolt://localhost',
      neo4j.auth.basic('neo4j', 'neo4j2'),
    )
  ), [])
  const query = async () => {
    const session = driver.session()
    const name = 'Alice'
    
    try {
      const result = await session.run(
        'CREATE (a:Person {name: $name}) RETURN a',
        { name },
      )
    
      const singleRecord = result.records[0]
      const node = singleRecord.get(0)
    
      console.log(node.properties.name)
    } finally {
      await session.close()
    }
  }

  useEffect(() => (() => { driver.close() }), [driver])
  
  return (
    <Button onClick={query}>¡Click Me!</Button>
  )
}