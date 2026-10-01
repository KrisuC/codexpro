import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';

// Retry only known read-only core operations after a confirmed closed transport.
// Timeouts and mutating calls have an unknown outcome and must never be replayed.
export const RETRYABLE_READS=new Set(['server_config','read','tree','search','show_changes','read_handoff']);
export function classify(error){
  if(error?.name==='AbortError')return 'cancelled';
  if((error?.code===-32000&&/connection closed|not connected/i.test(error?.message??''))||['EPIPE','ECONNRESET','ERR_STREAM_DESTROYED'].includes(error?.code))return 'connection_closed';
  if(error?.code===-32001)return 'timeout';
  if(error?.code===-32602)return 'invalid_arguments';
  if(error?.code===-32601)return 'unsupported_method';
  return error?.kind==='startup'?'startup_failed':'backend_error';
}
export function timeoutFor(name,args,config={}){
  const normal=config.requestTimeoutMs??120000;
  if(name==='bash')return Math.max(normal,Math.min(Math.max(Number(args.timeout_ms)||30000,1000),900000)+15000);
  if(name==='wait_for_handoff')return Math.max(normal,Math.min(Number(args.timeout_ms)||30000,900000)+15000);
  return normal;
}
export function conversationKey(meta){
  const value=meta?.['openai/session'];
  return typeof value==='string'&&value.length>0&&value.length<1024?createHash('sha256').update(value).digest('hex'):null;
}
export function createDiagnostics(directory){
  let sequence=0;
  const file=directory?path.join(directory,`gateway-${process.pid}.jsonl`):null;
  return (event,fields={})=>{
    const record={time:new Date().toISOString(),id:`${process.pid}-${++sequence}`,event,...fields};
    if(file)try{
      // Inputs, outputs, credentials, raw errors and conversation IDs never go here.
      fs.mkdirSync(directory,{recursive:true});
      if(fs.existsSync(file)&&fs.statSync(file).size>1048576)fs.renameSync(file,file+'.previous');
      fs.appendFileSync(file,JSON.stringify(record)+'\n',{mode:0o600});
    }catch{} // Diagnostics must not make a successful operation fail.
    return record.id;
  };
}
