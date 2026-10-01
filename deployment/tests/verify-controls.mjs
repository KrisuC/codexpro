import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';

const [sourceFile,artifactDir]=process.argv.slice(2);
const privateFile=path.join(artifactDir,'controls-verification-config.json');
fs.copyFileSync(sourceFile,privateFile);
async function open(){
 const client=new Client({name:'controls-verification',version:'1'});
 const transport=new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('../launch-gateway.mjs',import.meta.url)),privateFile],stderr:'pipe'});
 transport.stderr?.resume();await client.connect(transport);return client;
}
const a=await open(),b=await open();
try{
 await a.callTool({name:'integration_set_enabled',arguments:{backend:'windows',enabled:false}});
 if((await b.listTools()).tools.some(t=>t.name.startsWith('windows_')))throw Error('Other session did not observe Windows disable');
 await b.callTool({name:'integration_set_enabled',arguments:{backend:'playwright',enabled:false}});
 const tools=(await a.listTools()).tools;
 if(tools.some(t=>t.name.startsWith('windows_')||t.name.startsWith('pw_')))throw Error('One session overwrote another integration toggle');
 const git=await a.callTool({name:'bash',arguments:{command:'git --version'}});
 if(git.isError||git.structuredContent?.exitCode!==0)throw Error('Core shell interrupted by optional integration controls');
 console.log('Cross-session optional integration controls preserve core Git and each other.');
}finally{await Promise.allSettled([a.close(),b.close()]);fs.unlinkSync(privateFile);}
