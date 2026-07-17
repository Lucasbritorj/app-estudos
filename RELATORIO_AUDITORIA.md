# Relatório de Auditoria — app_estudos (Meu Caminho Aprovado)

> Derivado do `LEDGER_DE_AUDITORIA.md`. Auditoria autônoma de segurança
> (skill `security-audit-loop`), branch `audit/loop-2026-07-16`, base `3640a74`.
> Auditor: Claude Fable 5. **Merge é decisão humana — entregue para revisão, não mesclado.**

## Sumário executivo

- **Contexto:** app Flutter local-first (Hive CE), **sem backend de rede**. O prompt original pedia auditoria de Supabase + Vercel; verificação de código provou que **não há Supabase nem qualquer dependência de rede** (pubspec + `lib/` varridos). A auditoria RLS/JWT/CORS ficou como blueprint para migração futura (fora deste relatório); o trabalho executável incidiu sobre as **bordas de dado externo reais**: import de `.xlsx`, backup JSON colado e export CSV.
- **Achados por severidade:** Crítico 0 · Alto 0 · Médio 3 (A-001, A-002, A-003) · Baixo 2 (A-004, A-005)
- **Estado:** CORRIGIDO 4 (A-001…A-004) · ESCALADO 1 (A-005) · REQUER-VERIFICAÇÃO-HUMANA 1 (RV-001)
- **Suíte:** baseline 293/293 verdes → **312/312 verdes** (+19 testes de segurança), zero regressão. `flutter analyze` limpo. OSV: zero CVEs em 126 pacotes (antes e depois).
- **Verificação final:** juiz em contexto limpo (subagente) reprovou a v1 de A-001 (bypass de zip bomb via `f.size`); recorrigido em A-001b com descompressão limitada por bytes reais.
- **Orçamento:** 6 iterações de 10; ~180 linhas de diff de produção de ~500; dentro do limite.

---

## Achados (5W2H)

### A-001 — Zip bomb / exaustão de memória no leitor de .xlsx · Médio · CONFIRMADO · CORRIGIDO

- **What:** `XlsxReader` alocava linhas/células segundo os atributos `r` do XML (refs até `r="2000000"`/coluna `ZZZ`) e materializava partes descomprimidas sem teto sobre os **bytes reais** (CWE-400/CWE-1284, STRIDE-Denial of Service).
- **Why:** um `.xlsx` hostil trava/derruba o app por OOM. Duas vertentes: refs gigantes ditando alocação; e zip bomb (header do zip declara tamanho pequeno, conteúdo expande para GBs).
- **Where:** [lib/domain/xlsx_reader.dart](lib/domain/xlsx_reader.dart).
- **When:** presente desde a introdução do leitor. Severidade **Médio**: app local single-user, arquivo escolhido pelo próprio usuário no file picker; pior caso é OOM do próprio app, sem perda de dado (crash antes do merge), sem impacto cross-user.
- **Who:** o próprio usuário que for induzido a importar uma planilha maliciosa.
- **How:** vetor = arquivo `.xlsx` de origem não confiável. Correção (princípio: *nunca dimensionar processamento por dado controlado pelo atacante*): (1) tetos de linha/coluna nos limites reais do Excel; (2) descompressão via `Inflate.stream(raw, output: _SaidaLimitada)` — chamando o inflate Dart puro do `archive` **diretamente** com um `OutputStream` que aborta assim que os **bytes reais** passam do teto, cortando a inflação bloco a bloco antes de materializar o payload; (3) teto no tamanho do arquivo de entrada. Duas rodadas de reprovação do juiz foram necessárias: a primeira tentativa confiava em `f.size` (header mentiroso); a segunda usava `f.decompress`, que **na web** (alvo Vercel) materializa a parte inteira antes do teto agir (`_zlib_decoder_web.dart` chama `Inflate.stream` sem repassar o output). A v3 chama `Inflate` direto — `inflate.dart` não tem ramo de plataforma, então o corte é incremental em web e nativo.
- **How much:** correção contida no leitor + classe de stream auxiliar; ~110 linhas.
- **Evidência:** Red — a lógica `f.size` materializou 65730 bytes reais apesar de teto 4096 e header mentindo 1000 (script isolado). Green de pico — payload real de 5 MB, teto 64 KB → pico materializado 65534 bytes (não 5 MB), provando corte durante a inflação. Suíte: `test/xlsx_reader_seguranca_test.dart` (6 casos), 312/312 verdes.

### A-002 — CSV/formula injection no export · Médio · CONFIRMADO · CORRIGIDO

- **What:** `ExportService` escrevia células iniciadas em `= + - @` (tab/CR) sem neutralização (CWE-1236). Aspas de CSV **não** neutralizam fórmula.
- **Why:** nome de matéria/tópico/tarefa/comentário pode vir de planilha ou edital de terceiro; abrir o CSV exportado no Excel executaria a fórmula na máquina de quem abre (ex.: exfiltração via `=HYPERLINK`).
- **Where:** [lib/domain/export_service.dart](lib/domain/export_service.dart) — `_campo`/`_campoBi`.
- **When:** desde a existência do export CSV. Urgência média — depende de o usuário abrir o arquivo exportado.
- **Who:** quem abrir o CSV/BI exportado (o próprio usuário ou terceiro com quem ele compartilha).
- **How:** correção (princípio: *neutralizar dado na fronteira de saída conforme o interpretador de destino*): `_semFormula` prefixa apóstrofo nos gatilhos; Excel exibe o texto integral sem executar. Campos numéricos não passam pelo filtro.
- **How much:** ~15 linhas, sem mudança de assinatura.
- **Evidência:** Red — `test/export_csv_injection_test.dart` com `=HYPERLINK`/`+SOMA`/`@`/`-` crus na célula. Green — regex confirma nenhuma célula iniciada em gatilho; conteúdo preservado com apóstrofo.

### A-003 — Backup hostil fura o contrato FormatException · Médio · CONFIRMADO · CORRIGIDO

- **What:** `ImportService.parseBackup` fazia `(v as num)` no campo `planejamento` sem validação (CWE-755/CWE-20). A UI captura **somente** `FormatException`.
- **Why:** valor não numérico lançava `TypeError`, furava o `catch` da UI e virava exceção não tratada (crash); valor negativo entrava cru na meta semanal.
- **Where:** [lib/domain/import_service.dart](lib/domain/import_service.dart); UI em [lib/features/exportar/exportar_screen.dart](lib/features/exportar/exportar_screen.dart) (linhas 367, 437).
- **When:** desde o parser de backup. Impacto = crash real na borda de import.
- **Who:** usuário que cola um backup adulterado/corrompido.
- **How:** correção (princípio: *validar na borda de confiança, converter falha no contrato esperado*): `is! num` → `FormatException` com o dia ofensor; minutos clampados a ≥ 0.
- **How much:** ~8 linhas.
- **Evidência:** Red — `test/import_service_seguranca_test.dart` (valor string → TypeError; negativo cru). Green — FormatException + clamp; 302/302 na época.

### A-004 — Invariantes de modelo furadas por backup adulterado · Baixo · CONFIRMADO · CORRIGIDO

- **What:** `Materia.fromJson`/`Topico.fromJson` aceitavam `peso ≤ 0`; `RegistroHora` gerava contagem de páginas negativa com intervalo invertido/página negativa (CWE-20).
- **Why:** `peso ≤ 0` envenena a média ponderada da prontidão e a fila do planejamento; páginas negativas contaminam ritmo/stats. A UI já impõe `peso ≥ 1`, mas o import de backup não.
- **Where:** [lib/data/models/materia.dart](lib/data/models/materia.dart), [lib/data/models/topico.dart](lib/data/models/topico.dart), [lib/data/models/registro_hora.dart](lib/data/models/registro_hora.dart).
- **When:** desde os modelos. Severidade Baixo — corrupção confinada aos próprios dados de quem importa.
- **Who:** usuário que importa backup adulterado.
- **How:** correção (princípio: *invariante do domínio vale em toda via de construção, não só na UI*): clamp `peso ≥ 1` no `fromJson` (consistente com o precedente já existente no import de xlsx); página negativa → null; intervalo invertido → null no getter `paginasLidas` (ponto único de leitura).
- **How much:** ~20 linhas.
- **Evidência:** Red — `test/modelos_seguranca_test.dart` (5 casos). Green — 309/309.

### A-005 — Hive sem cifra em repouso · Baixo · CONFIRMADO · ESCALADO

- **What:** dados persistidos em Hive (desktop: arquivo; web: IndexedDB) sem cifra (STRIDE-Information Disclosure).
- **Why / Who / How much:** ver bloco "Itens escalados" abaixo — decisão de produto, não fechada unilateralmente.

---

## Anexos

### SBOM
[SBOM.md](SBOM.md) — 123 pacotes (pubspec.lock), todos `hosted` com sha256, zero dependências `git`/`path`. OSV (2026-07-16): zero CVEs conhecidas.

### Segredos que precisam de rotação
**Nenhum.** Varredura do histórico completo do repo (17 commits) por padrões de chave/token/credencial: dentro de `app_estudos/`, zero ocorrências. (Hits fora de escopo estão em `apex-recruiter/` e `Asimov/` — outros projetos do monorepo, com `process.env.GEMINI_API_KEY` corretamente via ambiente, não hardcoded.)

### Itens escalados (decisão humana)
- **A-005 — cifra em repouso.** Dois modelos de ameaça: (M1) atacante com sessão interativa na máquina — cifra com chave local é decorativa; (M2) disco/backup roubado a frio — chave derivada de PIN **mitigaria**, não é teatro. **Recomendação: aceitar o risco (a)** por proporcionalidade — dados são horas de estudo/notas/progresso, sem financeiro/saúde/credencial, e o custo de UX de PIN (recuperação, risco de perda total dos dados) supera o ganho. Reabrir com `HiveAesCipher` se o público-alvo passar a ter dado sensível.

### Requer verificação humana (fora do alcance do repo)
- **RV-001 — Vercel (quando o deploy ocorrer):** ativar Deployment Protection nos previews; conferir headers ativos (`curl -I https://<dominio>`, meta nota A em securityheaders.com); MFA na conta Vercel. A config de CSP/headers já está em [web/vercel.json](web/vercel.json).
