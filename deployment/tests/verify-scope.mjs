import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';

// Use two synthetic overlapping windows. Never retain the metadata-only list
// of the user's other windows in the verification report.
const [configFile,targetFile,backgroundFile,outputDir]=process.argv.slice(2);
const json=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const text=result=>result.content.filter(c=>c.type==='text').map(c=>c.text).join('\n');
async function open(configPath){
 const client=new Client({name:'window-scope-verification',version:'1'});
 const transport=new StdioClientTransport({command:process.execPath,args:[fileURLToPath(new URL('../launch-gateway.mjs',import.meta.url)),configPath],stderr:'pipe'});
 transport.stderr?.resume();
 await client.connect(transport,{timeout:45000});
 return client;
}
const target=json(targetFile),background=json(backgroundFile),records=[];
const client=await open(configFile);
try{
 for(const args of [{},{region:null},{region:[]},{region:[1,2,3]},{region:'not-json'}]){
  const result=await client.callTool({name:'windows_Screenshot',arguments:args});
  if(!result.isError||result.content.some(c=>c.type==='image'))throw Error('Invalid screenshot scope was not rejected');
 }
 const refused=await client.callTool({name:'windows_Snapshot',arguments:{use_ui_tree:true}});
 if(!refused.isError)throw Error('Unscoped UI extraction was not rejected');
 records.push('invalid and unscoped image/UI requests rejected');
 const scoped=await client.callTool({name:'windows_Snapshot',arguments:{region:target.region,use_ui_tree:true,use_vision:false}},undefined,{timeout:90000});
 if(scoped.isError||!text(scoped).includes(target.title)||text(scoped).includes(background.title)||text(scoped).includes(background.value))throw Error('Snapshot scope failed: '+JSON.stringify({toolError:!!scoped.isError,targetFound:text(scoped).includes(target.title),backgroundTitleFound:text(scoped).includes(background.title),backgroundControlFound:text(scoped).includes(background.value),captureError:text(scoped).match(/Error capturing desktop state:[^\n]{0,180}/)?.[0]??null}));
 records.push('scoped UI identifies target and excludes overlapping background metadata/text');
 const metadata=await client.callTool({name:'windows_Snapshot',arguments:{}},undefined,{timeout:90000});
 if(metadata.isError||!text(metadata).includes(target.title)||text(metadata).includes(background.value)||metadata.content.some(c=>c.type==='image'))throw Error('Metadata-only discovery included UI text/image or failed');
 records.push('unscoped discovery returns window metadata without test control text/image');
 const screenshot=await client.callTool({name:'windows_Screenshot',arguments:{region:target.region,use_annotation:false}},undefined,{timeout:90000});
 const image=screenshot.content.find(c=>c.type==='image');
 if(!image||screenshot.isError)throw Error('Scoped screenshot missing');
 const bytes=Buffer.from(image.data,'base64');
 if(bytes.toString('hex',0,8)!=='89504e470d0a1a0a'||bytes.readUInt32BE(16)!==target.region[2]-target.region[0]||bytes.readUInt32BE(20)!==target.region[3]-target.region[1])throw Error('Screenshot dimensions do not match target');
 fs.writeFileSync(path.join(outputDir,'window-scope.png'),bytes);
 records.push('screenshot size matches target window rectangle');
 await client.callTool({name:'windows_Click',arguments:{loc:target.close}});
 await new Promise(resolve=>setTimeout(resolve,250));
 await client.callTool({name:'windows_Click',arguments:{loc:background.close}});
}finally{await client.close();}
const faultConfig=json(configFile);
faultConfig.backends.windows.command=path.join(outputDir,'nonexistent-verification-backend.exe');
const faultFile=path.join(outputDir,'fault-verification-config.json');
fs.writeFileSync(faultFile,JSON.stringify(faultConfig));
const faulty=await open(faultFile);
try{
 const failure=await faulty.callTool({name:'windows_Snapshot',arguments:{}},undefined,{timeout:90000});
 if(!failure.isError)throw Error('Invalid backend unexpectedly worked');
 const git=await faulty.callTool({name:'bash',arguments:{command:'git --version'}});
 if(git.isError||git.structuredContent?.exitCode!==0)throw Error('Optional backend failure affected core shell');
 records.push('failed Windows backend does not interrupt core Git');
}finally{await faulty.close();fs.unlinkSync(faultFile);}
fs.writeFileSync(path.join(outputDir,'scope-verification.json'),JSON.stringify({passed:true,records},null,2));
console.log(JSON.stringify({passed:true,records}));
