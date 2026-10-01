import fs from 'node:fs';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import {makeMcpEnv} from './env.mjs';
const definition=JSON.parse(fs.readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,''));
const client=new Client({name:'integration-discovery',version:'1'});
const transport=new StdioClientTransport({...definition,env:makeMcpEnv(process.env,definition.env??{}),stderr:'pipe'});
transport.stderr?.resume();
try{
 await client.connect(transport,{timeout:90000});
 const tools=await client.listTools({}, {timeout:90000});
 fs.writeFileSync(process.argv[3],JSON.stringify(tools,null,2));
 console.log(JSON.stringify({server:client.getServerVersion(),tools:tools.tools.map(t=>t.name)}));
}finally{await client.close();}
