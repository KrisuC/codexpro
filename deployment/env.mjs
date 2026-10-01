// MCP subprocesses do not inherit the tunnel's credentials or arbitrary parent env.
const SYSTEM_NAMES = new Set([
  'PATH', 'PATHEXT', 'SYSTEMROOT', 'SYSTEMDRIVE', 'WINDIR', 'COMSPEC',
  'TEMP', 'TMP', 'USERPROFILE', 'HOMEDRIVE', 'HOMEPATH', 'APPDATA', 'LOCALAPPDATA',
  'PROGRAMFILES', 'PROGRAMFILES(X86)', 'PROGRAMW6432', 'USERNAME', 'USERDOMAIN',
  'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_IDENTIFIER'
]);
const TUNNEL_SECRETS = new Set(['CONTROL_PLANE_API_KEY', 'OPENAI_API_KEY', 'OPENAI_ADMIN_KEY']);
export function makeMcpEnv(parent = process.env, explicit = {}) {
  const env = {};
  for (const [name, value] of Object.entries(parent))
    if (SYSTEM_NAMES.has(name.toUpperCase()) && value !== undefined) env[name] = value;
  for (const [name, value] of Object.entries(explicit)) {
    if (TUNNEL_SECRETS.has(name.toUpperCase())) throw new Error('Tunnel credentials cannot be forwarded to MCP backends');
    if (typeof value !== 'string') throw new Error('Explicit environment values must be strings');
    env[name] = value;
  }
  return env;
}
