const fs = require('fs');
const timestamp = Date.now();

let sw = fs.readFileSync('sw.js', 'utf8');
sw = sw.replace('__DEPLOY_TIME__', timestamp);
fs.writeFileSync('sw.js', sw);

console.log(`✅ sw.js atualizado com cache version: thegrint-pool-${timestamp}`);
