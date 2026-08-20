const fs = require('fs');
const path = require('path');
function walk(dir) { let n=0, bytes=0; for (const e of fs.readdirSync(dir,{withFileTypes:true})) { const p=path.join(dir,e.name); if(e.isDirectory()){const x=walk(p);n+=x.n;bytes+=x.bytes;} else {n++;bytes+=fs.statSync(p).size;} } return {n,bytes}; }
for (const p of process.argv.slice(2)) console.log(p, walk(p));
