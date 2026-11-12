import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

test('launcher preflight, both installation paths and repeated launch', {skip:process.platform!=='win32'}, () => {
  const output=execFileSync('powershell.exe',['-NoProfile','-File',fileURLToPath(new URL('test-launcher.ps1',import.meta.url))],{encoding:'utf8',timeout:20000});
  for(const scenario of ['missing','other-debugger','regular','store','explicit','ready'])assert(output.includes(`PASS: ${scenario}`));
});
