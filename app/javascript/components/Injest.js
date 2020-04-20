import React, { useState } from "react"
import { Button } from "antd"
import 'antd/dist/antd.css'

export default (props) => {
  const [log, setLog] = useState()

  const onClick = () => {
    fetch('/ingest', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(props)
    })
    .then(res => res.text())
    .then(setLog)
  }

  return log ? <pre>{log}</pre> : <Button onClick={onClick} type='primary' danger={props.existing}>⏩ Injest ⏭</Button>
}