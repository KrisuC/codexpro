import {makeMcpEnv} from './env.mjs';
// Scrub before importing third-party modules as well as before spawning backends.
const environment=makeMcpEnv(process.env);
for(const key of Object.keys(process.env))delete process.env[key];
Object.assign(process.env,environment);
await import('./gateway.mjs');
