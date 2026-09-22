// Smoke público opcional; não usa credenciais nem altera dados remotos.
const {sourceUrl,readSafe,parse,verifyDocuments}=require('./coletor.cjs');
(async()=>{
 for(const [fonte,id] of [['fgv','seplagrj'],['cebraspe','AGEPAR_PR_26'],['cesgranrio','sema-mt-2026']]){
  const catalog=parse(fonte,await readSafe(sourceUrl(fonte)));
  const detail=parse(fonte,await readSafe(sourceUrl(fonte,id)),id);
  const verified=await verifyDocuments(detail);
  console.log(JSON.stringify({fonte,catalogo:catalog.length,documentos:detail.length,verificados:verified.filter(v=>v.checksum).length,pendencias:verified.filter(v=>!v.checksum).map(v=>v.verificacao)}));
 }
})().catch(e=>{console.error(e.message);process.exitCode=1;});
