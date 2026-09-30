const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {parse, sourceUrl, readSafe,verifyDocuments}=require('./coletor.cjs');
for(const [source,file] of [['fgv','fgv.html'],['cebraspe','cebraspe.json']]) test(`fixture oficial ${source}`,()=>{
 const rows=parse(source,fs.readFileSync(`${__dirname}/fixtures/${file}`,'utf8'));
 assert.ok(rows.length>3); assert.equal(new Set(rows.map(x=>x.id)).size,rows.length);
 assert.ok(rows.every(x=>x.url.startsWith('https://')&&x.titulo.length>2));
 assert.deepEqual(rows,parse(source,fs.readFileSync(`${__dirname}/fixtures/${file}`,'utf8')));
});
test('detalhe Cebraspe extrai editais datados',()=>assert.ok(parse('cebraspe',fs.readFileSync(`${__dirname}/fixtures/cebraspe-detalhe.json`,'utf8'),'AGEPAR_PR_26').some(x=>x.data&&x.titulo.includes('Retificação'))));
test('URL arbitrária, travessia e fonte inválida rejeitadas',()=>{for(const id of ['https://localhost/','../admin','x?foo=1','%2e%2e']) assert.throws(()=>sourceUrl('fgv',id));assert.throws(()=>sourceUrl('evil'));});
test('HTML alterado ou vazio não vira sucesso',()=>assert.throws(()=>parse('fgv','<html>login</html>')));
test('redirecionamento externo bloqueado',async()=>assert.rejects(readSafe('https://conhecimento.fgv.br/concursos',async()=>new Response('',{status:302,headers:{location:'http://127.0.0.1/'}})),/destino/));
test('erro HTTP explícito',async()=>assert.rejects(readSafe(sourceUrl('fgv'),async()=>new Response('',{status:503})),/503/));
test('resposta grande bloqueada',async()=>assert.rejects(readSafe(sourceUrl('fgv'),async()=>new Response('x'.repeat(2_000_001))),/limite/));
test('PDF alterado na mesma URL altera versão',async()=>{
 const rows=[{url:sourceUrl('fgv'),versao:'original'}];
 const a=await verifyDocuments(rows,async()=>new Response('PDF1'));
 const b=await verifyDocuments(rows,async()=>new Response('PDF2'));
 assert.notEqual(a[0].versao,b[0].versao);assert.equal(a[0].url,b[0].url);
});
test('documento excessivo permanece explicitamente não verificado',async()=>{
 const [r]=await verifyDocuments([{url:sourceUrl('fgv'),versao:'v'}],async()=>new Response('x'.repeat(2_000_001)));
 assert.match(r.verificacao,/Não verificado/);assert.equal(r.versao,'v');
});
