// Plain-HTTP listener for biometric devices that can't do TLS.
// Forwards every request straight through to the Supabase edge function over HTTPS.
const http = require('http')
const https = require('https')

const TARGET_HOST = 'orlqjhqxeyukvfzsursl.supabase.co'
const PORT = process.env.PORT || 80

http.createServer((req, res) => {
  const chunks = []
  req.on('data', c => chunks.push(c))
  req.on('end', () => {
    const body = Buffer.concat(chunks)
    const proxyReq = https.request({
      host: TARGET_HOST,
      path: '/functions/v1/biometric-adms' + req.url,
      method: req.method,
      headers: { ...req.headers, host: TARGET_HOST },
    }, proxyRes => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers)
      proxyRes.pipe(res)
    })
    proxyReq.on('error', err => {
      res.writeHead(502)
      res.end('Bridge error: ' + err.message)
    })
    proxyReq.write(body)
    proxyReq.end()
  })
}).listen(PORT, () => {
  console.log(`Biometric bridge listening on port ${PORT}, forwarding to ${TARGET_HOST}`)
})
