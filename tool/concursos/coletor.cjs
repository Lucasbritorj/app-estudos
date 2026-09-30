const {createHash}=require('node:crypto');
const SOURCES={fgv:'https://conhecimento.fgv.br/concursos',cebraspe:'https://apis.cebraspe.org.br/cebraspe/eventos/tipo/concursos/'};
const HOSTS=new Set(['conhecimento.fgv.br','apis.cebraspe.org.br','www.cebraspe.org.br','cdn.cebraspe.org.br']);
function safe(url){const u=new URL(url);if(u.protocol!=='https:'||!HOSTS.has(u.hostname)||u.port||u.username||u.password)throw Error('destino não permitido');return u.href;}
function sourceUrl(fonte,id=''){if(!Object.hasOwn(SOURCES,fonte)||typeof id!=='string'||(id&&!/^[a-zA-Z0-9_-]{1,100}$/.test(id)))throw Error('fonte ou concurso inválido');return id?({fgv:`https://conhecimento.fgv.br/concursos/${id}`,cebraspe:`https://apis.cebraspe.org.br/cebraspe/eventos/${id}`})[fonte]:SOURCES[fonte];}
async function readSafe(url,fetcher=fetch,binary=false){const signal=AbortSignal.timeout(8000);for(let i=0;i<4;i++){const r=await fetcher(safe(url),{redirect:'manual',signal,headers:{accept:'application/json,text/html,application/pdf','user-agent':'AppEstudos/1.0 (consulta publica)'}});if([301,302,303,307,308].includes(r.status)){url=safe(new URL(r.headers.get('location'),url).href);continue;}if(!r.ok)throw Error(`Fonte retornou HTTP ${r.status}`);if(Number(r.headers.get('content-length'))>2_000_000)throw Error('Resposta excedeu limite');let size=0;const chunks=[];for await(const chunk of r.body){size+=chunk.length;if(size>2_000_000)throw Error('Resposta excedeu limite');chunks.push(chunk);}return binary?Buffer.concat(chunks):Buffer.concat(chunks).toString('utf8');}throw Error('Redirecionamentos em excesso');}
const hash=s=>createHash('sha256').update(s).digest('hex');
const clean=s=>String(s??'').replace(/<[^>]*>/g,' ').replace(/&(?:amp|nbsp|quot|lt|gt);/g,x=>({'&amp;':'&','&nbsp;':' ','&quot;':'"','&lt;':'<','&gt;':'>'})[x]).replace(/&#(\d+);/g,(_,n)=>String.fromCodePoint(Number(n))).replace(/\s+/g,' ').trim();
function row(fonte,url,titulo,data=null,concurso=null,salario=null){url=safe(url);const value={fonte,url,titulo:clean(titulo),data,concurso,salario,escolaridade:null,localizacao:null};return {...value,id:hash(`${fonte}:${url}`),versao:hash(JSON.stringify(value))};}
function parse(fonte,body,id=''){
 const result=[];
 if(fonte==='cebraspe'){
  const data=JSON.parse(body);
  if(id){for(const a of data.arquivosEdital??[]){if(!a.nomeArquivo||!/^_[.]?(pdf|html)$/i.test(a.tipoExtensaoArquivo??''))continue;result.push(row(fonte,`https://cdn.cebraspe.org.br/concursos/${id}/arquivos/${encodeURIComponent(a.nomeArquivo)}`,a.descricaoArquivo,a.dataArquivoObj??null,id));}}
  else{if(!Array.isArray(data))throw Error('Formato da fonte mudou');for(const group of data){if(/encerrad/i.test(group.faseEvento))continue;for(const e of group.eventos??[])if(/^[\w-]+$/.test(e.eventoURL))result.push(row(fonte,`https://www.cebraspe.org.br/concursos/${e.eventoURL}`,e.eventoNomeAbreviado,null,e.eventoURL,e.eventoSalarioMaximo??null));}}
 }else{
  const base=sourceUrl(fonte,id);
  for(const m of body.matchAll(/<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)){
   const title=clean(m[2]);if(title.length<3||/nosso portf[oó]lio/i.test(title))continue;
   let u;try{u=new URL(m[1].replace(/&amp;/g,'&'),base);safe(u.href);}catch{continue;}
   const catalog=u.hostname==='conhecimento.fgv.br'&&/^\/concursos\/[\w-]+\/?$/.test(u.pathname);
   const document=id&&(/\.(pdf|html)$/i.test(u.pathname)||(/edital|retifica|comunicado/i.test(title)&&u.href!==base));
   if(!id&&!catalog||id&&!document)continue;
   result.push(row(fonte,u.href,title,null,id||u.pathname.split('/').filter(Boolean).at(-1)));
  }
 }
 const unique=[...new Map(result.map(x=>[x.id,x])).values()];
 if(!unique.length)throw Error('Sem dados reconhecíveis: fonte vazia ou formato alterado');
 return unique;
}
async function verifyDocuments(rows,fetcher=fetch){
 return Promise.all(rows.map(async(row,index)=>{
  if(index>=12)return {...row,verificacao:'Não verificado: limite de 12 documentos por consulta'};
  try{const bytes=await readSafe(row.url,fetcher,true);const checksum=hash(bytes);return {...row,checksum,versao:hash(`${row.versao}:${checksum}`),verificacao:'Conteúdo verificado (SHA-256)'};}
  catch(e){return {...row,verificacao:`Não verificado: ${e.message}`};}
 }));
}
module.exports={sourceUrl,readSafe,parse,verifyDocuments};
