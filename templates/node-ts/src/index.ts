import { createServer } from "node:http";

const port = Number(process.env.PORT ?? 3000);

createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ ok: true, stack: "node-ts", time: new Date().toISOString() }));
}).listen(port, () => {
  console.log(`kit-sample-ts listening on :${port}`);
});
