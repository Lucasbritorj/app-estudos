const {sourceUrl,readSafe,parse,verifyDocuments}=require('../tool/concursos/coletor.cjs');
module.exports=async(req,res)=>{
 if(req.method!=='GET'){res.setHeader('Allow','GET');return res.status(405).json({erro:'Método não permitido'});}
 const {fonte,concurso='',...extra}=req.query;
 let url;try{if(Object.keys(extra).length)throw Error();url=sourceUrl(fonte,concurso);}catch{return res.status(400).json({erro:'Informe uma fonte e um identificador de concurso válidos.'});}
 try{let publicacoes=parse(fonte,await readSafe(url),concurso);if(concurso)publicacoes=await verifyDocuments(publicacoes);res.setHeader('Cache-Control','public, s-maxage=18000, stale-while-revalidate=3600');return res.status(200).json({fonte,concurso,consultadoEm:new Date().toISOString(),publicacoes});}
 catch(e){return res.status(502).json({erro:e.name==='TimeoutError'?'Fonte excedeu tempo de resposta':e.message});}
};
