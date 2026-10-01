import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
const configFile=process.argv[2],stateFile=process.argv[3],outputDir=process.argv[4];
const readJson=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const client=new Client({name:'controlled-acceptance',version:'1'});
const transport=new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('../launch-gateway.mjs',import.meta.url)),configFile],env:{...process.env,CONTROL_PLANE_API_KEY:'AUDIT_SECRET_MUST_NOT_REACH_BACKENDS',AWS_SECRET_ACCESS_KEY:'AUDIT_SECRET_MUST_NOT_REACH_BACKENDS'},stderr:'pipe'});
transport.stderr?.resume();
const records=[];
async function call(name,args={}){
 const r=await client.callTool({name,arguments:args},undefined,{timeout:90000});
 if(r.isError)throw Error(`Tool failed: ${name}: `+r.content.filter(x=>x.type==='text').map(x=>x.text).join('\n'));
 records.push({tool:name,success:true});return r;
}
const text=r=>r.content.filter(x=>x.type==='text').map(x=>x.text).join('\n');
function image(r,file){const i=r.content.find(x=>x.type==='image');if(!i)throw Error('Missing screenshot image');fs.writeFileSync(path.join(outputDir,file),Buffer.from(i.data,'base64'));}
const fixtureServer=http.createServer((req,res)=>{
 if(req.url==='/verify'){res.setHeader('content-type','application/json');res.end('{"accepted":true}');return;}
 res.setHeader('content-type','text/html; charset=utf-8');
 res.end(`<!doctype html><title>CodexPro Playwright Acceptance</title><h1>Isolated browser test</h1><label>Test name <input id="name" aria-label="Test name"></label><button id="apply">Apply</button><output id="result">Not submitted</output><script>console.warn('synthetic-fixture-loaded');document.querySelector('#apply').onclick=async()=>{let v=document.querySelector('#name').value;localStorage.setItem('fixture',v);document.cookie='fixture=synthetic; SameSite=Strict';await fetch('/verify');document.querySelector('#result').textContent='Saved: '+v;console.warn('synthetic-fixture-submitted');};</script>`);
});
await new Promise(resolve=>fixtureServer.listen(0,'127.0.0.1',resolve));
const fixtureURL=`http://127.0.0.1:${fixtureServer.address().port}/`;
try{
 await client.connect(transport,{timeout:45000});
 const listed=await client.listTools();
 if(!listed.tools.some(t=>t.name==='bash')||!listed.tools.some(t=>t.name==='windows_Snapshot')||!listed.tools.some(t=>t.name==='pw_browser_navigate'))throw Error('Incomplete gateway discovery');
 const config=await call('server_config');
 if(!text(config).includes('full'))throw Error('Shell permission unexpectedly changed');
 await call('open_current_workspace');
 await call('read',{path:'README.md',start_line:1,end_line:3});
 const git=await call('bash',{command:'git status --short',timeout_ms:30000});
 if(git.structuredContent?.exitCode!==0)throw Error('Git status failed');
 const env=await call('bash',{command:"printf '%s|%s' \"\${CONTROL_PLANE_API_KEY-unset}\" \"\${AWS_SECRET_ACCESS_KEY-unset}\"",timeout_ms:30000});
 if(env.structuredContent?.stdout!=='unset|unset')throw Error('Parent secret leaked into shell environment');
 if(!process.argv.includes('--browser-only')){
 const state=readJson(stateFile);
 const snapshot=await call('windows_Snapshot',{region:state.region,use_vision:false,use_ui_tree:true});
 if(!text(snapshot).includes('Acceptance'))throw Error('Target test window not identified');
 await call('windows_Type',{text:'MCP controlled input',loc:state.input,clear:true});
 await call('windows_Click',{loc:state.apply});
 await new Promise(resolve=>setTimeout(resolve,500));
 const updated=readJson(stateFile);
 if(updated.result!=='PASS: MCP controlled input')throw Error('Desktop input/click not confirmed by test window');
 image(await call('windows_Screenshot',{region:state.region,use_annotation:false}),'windows-controlled-test.png');
 await call('windows_Click',{loc:state.close});
 }
 const nav=await call('pw_browser_navigate',{url:fixtureURL});
 const structure=await call('pw_browser_snapshot');
 if(!text(nav).includes('Isolated browser test')&&!text(structure).includes('Isolated browser test'))throw Error('Browser page structure not identified');
 await call('pw_browser_fill_form',{fields:[{name:'Test name',target:'#name',type:'textbox',value:'MCP browser input'}]});
 await call('pw_browser_click',{target:'#apply'});
 const result=await call('pw_browser_evaluate',{function:"() => ({result:document.querySelector('#result').textContent,storage:localStorage.getItem('fixture'),cookie:document.cookie})"});
 if(!text(result).includes('Saved: MCP browser input'))throw Error('Browser click result missing');
 const consoleMessages=await call('pw_browser_console_messages',{level:'warning'});
 if(!text(consoleMessages).includes('synthetic-fixture-submitted'))throw Error('Console probe missing');
 const network=await call('pw_browser_network_requests',{});
 if(!text(network).includes('/verify'))throw Error('Network probe missing');
 const screenshot=await call('pw_browser_take_screenshot',{scale:'css'});
 image(screenshot,'playwright-controlled-test.png');
 await call('pw_browser_close');
 await call('pw_browser_navigate',{url:fixtureURL});
 const reset=await call('pw_browser_evaluate',{function:"() => ({storage:localStorage.getItem('fixture'),cookie:document.cookie})"});
 if(text(reset).includes('MCP browser input')||text(reset).includes('fixture=synthetic'))throw Error('Isolated browser state unexpectedly persisted');
 await call('pw_browser_close');
 await call('integration_set_enabled',{backend:'windows',enabled:false});
 const disabled=await client.listTools();if(disabled.tools.some(t=>t.name.startsWith('windows_')))throw Error('Windows backend was not independently disabled');
 await call('bash',{command:'git --version'});
 await call('integration_set_enabled',{backend:'windows',enabled:true});
 fs.writeFileSync(path.join(outputDir,'local-acceptance.json'),JSON.stringify({status:'passed',tools:listed.tools.length,records,fixtureOnly:true,parentSecretsAbsent:true,browserStateReset:true},null,2));
 console.log(`Controlled acceptance passed: ${records.length} calls, ${listed.tools.length} tools.`);
}finally{
 await client.close();
 await new Promise(resolve=>fixtureServer.close(resolve));
}
