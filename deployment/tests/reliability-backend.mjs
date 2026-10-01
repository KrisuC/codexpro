import fs from 'node:fs';
import path from 'node:path';
import {Server} from '@modelcontextprotocol/sdk/server/index.js';
import {StdioServerTransport} from '@modelcontextprotocol/sdk/server/stdio.js';
import {ListToolsRequestSchema,CallToolRequestSchema,McpError,ErrorCode} from '@modelcontextprotocol/sdk/types.js';

const directory=process.argv[2];
let selected='ws_default';
const tools=['read','bash','server_config','open_workspace','open_current_workspace','codexpro'].map(name=>({name,description:'Synthetic verification tool',inputSchema:{type:'object',properties:['read','bash'].includes(name)?{workspace_id:{type:'string'}}:{},additionalProperties:true}}));
const server=new Server({name:'Synthetic backend',version:'1'},{capabilities:{tools:{}}});
server.setRequestHandler(ListToolsRequestSchema,async()=>({tools}));
server.setRequestHandler(CallToolRequestSchema,async request=>{
 const {name,arguments:args={}}=request.params;
 if(name==='open_workspace')selected=args.path==='a'?'ws_a':'ws_b';
 if(name==='open_current_workspace')selected='ws_default';
 if(name==='read'&&args.path==='invalid')throw new McpError(ErrorCode.InvalidParams,'Synthetic invalid arguments');
 if(name==='read'&&args.path==='slow')await new Promise(resolve=>setTimeout(resolve,650));
 if(name==='bash'&&args.command==='slow')await new Promise(resolve=>setTimeout(resolve,650));
 if(name==='read'&&args.path==='crash-once'){
  const marker=path.join(directory,'read-crashed');
  if(!fs.existsSync(marker)){fs.writeFileSync(marker,'once');process.exit(31);}
 }
 if(name==='bash'&&args.command==='crash-mutation'){
  const file=path.join(directory,'mutation-count');
  fs.writeFileSync(file,String((fs.existsSync(file)?Number(fs.readFileSync(file,'utf8')):0)+1));
  process.exit(32);
 }
 const result={pid:process.pid,workspace_id:args.workspace_id??selected,exitCode:0,stdout:'synthetic-ok'};
 return {content:[{type:'text',text:JSON.stringify(result)}],structuredContent:result};
});
await server.connect(new StdioServerTransport());
