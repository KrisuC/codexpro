import fs from 'node:fs';
import http from 'node:http';
const stateFile=process.argv[2];
const server=http.createServer((req,res)=>{
 if(req.url==='/verify'){res.setHeader('content-type','application/json');res.end('{"accepted":true}');return;}
 res.setHeader('content-type','text/html; charset=utf-8');
 res.end(`<!doctype html><title>CodexPro Remote Acceptance</title><h1>Isolated remote browser test</h1><label>Test name <input id="name" aria-label="Test name"></label><button id="apply">Apply</button><output id="result">Not submitted</output><script>console.warn('remote-fixture-loaded');document.querySelector('#apply').onclick=async()=>{let v=document.querySelector('#name').value;localStorage.setItem('fixture',v);document.cookie='fixture=synthetic; SameSite=Strict';await fetch('/verify');document.querySelector('#result').textContent='Saved: '+v;console.warn('remote-fixture-submitted');};</script>`);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
fs.writeFileSync(stateFile,JSON.stringify({pid:process.pid,url:`http://127.0.0.1:${server.address().port}/`}));
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>server.close(()=>process.exit(0)));
