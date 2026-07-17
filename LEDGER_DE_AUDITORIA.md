# Ledger de Auditoria — app_estudos (Meu Caminho Aprovado)

> **Estado vivo da auditoria.** Atualizado + commitado a cada achado fechado.

## Metadados

- **Branch de auditoria:** `audit/loop-2026-07-16`
- **Commit base:** `3640a74`
- **Data de início:** 2026-07-16
- **Auditor (modelo/versão):** Claude Fable 5 (claude-fable-5), skill security-audit-loop
- **Escopo:** `app_estudos/` — Flutter local-first (Hive CE), sem rede. Foco: bordas de entrada de dado externo (xlsx, backup JSON colado, edital colado), integridade de dados locais, preparação de deploy web estático (Vercel).

## Baseline funcional (Fase 0)

- **Testes existentes:** 293 (contagem canônica via reporter expanded; o "+277" do primeiro run compacto era artefato de `\r` no output persistido)
- **Passam:** 293  |  **Já falham (pré-existentes):** 0
- **Build baseline:** verde (`flutter build web --release` OK, 284s)
- **Lint baseline:** `flutter analyze` → `No issues found!`
- **Nota:** working tree carrega modificações não commitadas do dono do repo (feature em andamento). A auditoria commita **apenas** os arquivos que toca; arquivos-alvo são checados por status antes do commit.

## Orçamento global (Fase 0)

- **Máx. de iterações do loop:** 10  |  **Consumidas:** 0
- **Máx. de tamanho de diff (excl. ledger/relatório):** ~500 linhas  |  **Consumido:** 0
- **Máx. de tempo/execuções:** ~90 min de execuções de suíte/build
- **Ao esbarrar no limite:** relatório parcial, listar aberto, reportar.

## Inventário (Fase 0)

- **Linguagens/frameworks:** Dart 3.12 / Flutter (Riverpod 3, Hive CE, fl_chart, pdf, archive+xml)
- **Gerenciadores de pacote:** pub (pubspec.lock commitado, 126 pacotes)
- **Ferramentas de qualidade já no repo:** `flutter analyze` (flutter_lints 6), `flutter test` (277), `flutter build web`
- **CI:** inexistente.
- **SCA triagem (OSV API, 2026-07-16):** 126 pacotes consultados → **zero vulnerabilidades conhecidas**.

## Data Flow Diagram (Fase 1, textual)

```
[arquivo .xlsx do usuário]        → file_selector → XlsxReader.lerAbas (zip+XML em memória)
                                    → PlanilhaImportService.parse → repositorios.mesclar → Hive
[JSON de backup colado (TextField)] → ImportService.parseBackup → mesclar/substituir → Hive
[texto de edital colado]           → EditalParserService → matérias/tópicos → Hive
[dados Hive]                       → ExportService (CSV Excel pt-BR / CSV BI / JSON) → compartilhador (share_plus / download web)
[dados Hive]                       → pdf → share
[Hive]                             → box local (desktop: arquivo; web: IndexedDB, SEM cifra)
```

Fronteiras de confiança: (1) arquivo xlsx de origem externa; (2) JSON/edital colado (pode vir de terceiros); (3) CSV exportado aberto no Excel do usuário; (4) armazenamento local em máquina possivelmente compartilhada.

## Superfície de ataque (Fase 1)

- Import .xlsx (`xlsx_reader.dart`) — upload de arquivo não confiável
- Import backup JSON (`import_service.dart` via TextField) — texto não confiável
- Import edital (`edital_parser_service.dart` via texto colado) — texto não confiável
- Export CSV aberto no Excel (`export_service.dart`) — injeção de fórmula no consumidor
- Hive em repouso (IndexedDB no web) — leitura local por terceiro com acesso à máquina/perfil

## STRIDE por componente (Fase 1)

| Componente | S | T | R | I | D | E | Observação |
|---|---|---|---|---|---|---|---|
| XlsxReader | – | ✓ | – | – | **✓** | – | zip/XML hostil: alocação dirigida por atributos `r` sem teto (linhas/colunas) |
| ImportService | – | ✓ | – | – | ✓ | – | `TypeError` escapa do contrato FormatException (campo `planejamento`) |
| ExportService | – | – | – | ✓ | – | – | CSV sem neutralização de fórmula (`=`,`+`,`-`,`@`) → execução no Excel do usuário |
| EditalParser | – | ✓ | – | – | – | – | regex lineares, sem ReDoS; tryParse em números |
| Hive (web) | – | ✓ | – | ✓ | – | – | sem cifra em repouso; ameaça = acesso local ao perfil do navegador |
| App web (Vercel) | – | ✓ | – | – | – | – | mitigado pré-auditoria: CSP/headers em `web/vercel.json` (commit de preparação) |

## Fila priorizada por risco (probabilidade × impacto)

1. **A-001** — XlsxReader: exaustão de memória por refs `r` sem teto e por zip bomb (CWE-400/CWE-1284, STRIDE-D). Arquivo hostil trava/derruba o app. Severidade rebaixada de Alto→**Médio** na verificação final: app local single-user, arquivo escolhido pelo próprio usuário no file picker; pior caso é OOM do próprio app (sem perda de dado — crash antes do merge; sem impacto cross-user, sem escalada). DoS local, não High.
2. **A-002** — ExportService: CSV/formula injection (CWE-1236, OWASP A03-adjacent). Dado vindo de xlsx/edital de terceiro executa fórmula no Excel da vítima. **Médio**
3. **A-003** — ImportService: `(v as num)` em `planejamento` lança TypeError que fura o `on FormatException` da UI (CWE-755/CWE-20). **Médio**
4. **A-004** — Modelos: `peso`/`corSlot`/páginas sem clamp no `fromJson` (integridade; `corDaSerie` usa `%`, sem crash). **Baixo**
5. **A-005** — Hive web sem cifra em repouso (Information Disclosure local). Decisão de produto (chave local não protege contra o mesmo atacante). **ESCALAR**

## Ocorrências operacionais

- **2026-07-17 — commit externo na branch de auditoria.** `d2a011f visual` (feature do dono do repo, ~250 linhas: quests/stats/gamificação) entrou entre A-001 e A-002 porque a working tree é compartilhada com o IDE do usuário. O commit varreu também `test/export_csv_injection_test.dart` (conteúdo idêntico ao escrito pela auditoria; verificado por status limpo). Decisão: não reescrever histórico de trabalho alheio; a separação por natureza de risco no encerramento sai via cherry-pick dos commits `fix(A-00x)`/`chore(audit)`. Suíte completa verde (298/298) sobre o estado combinado.

## Registro de achados

| ID | Fase | Classe | Severidade | Conf. | Estado | Commit | Evidência (Red → Green) |
|---|---|---|---|---|---|---|---|
| A-001 | 2 | CWE-400/CWE-1284, STRIDE-D | Médio | CONFIRMADO | CORRIGIDO | (commits A-001, A-001b, A-001c) | v1 (50e6168): tetos de linha/coluna por ref `r`. **Juiz reprovou v1**: teto usava `f.size` (header do zip, controlado pelo atacante) → bypass provado (366KB→80MB). v2 (A-001b, c262ce1): `f.decompress(_SaidaLimitada)`. **Juiz reprovou v2**: na web (alvo Vercel) `f.decompress`→`_zlib_decoder_web.dart:87` faz `Inflate.stream(input).getBytes()` SEM repassar output → materializa a parte inteira antes do teto agir (measure-after, pico livre). v3 (A-001c): chama `Inflate.stream(raw.getStream(decompress:false), output: _SaidaLimitada)` DIRETO — `inflate.dart` é Dart puro sem ramo de plataforma, escreve bloco a bloco no teto em web E nativo. Provado por script: payload real de 5 MB, teto 64 KB → **pico materializado 65534 bytes** (não 5 MB). Green: 312/312 verdes |
| A-002 | 2 | CWE-1236 | Médio | CONFIRMADO | CORRIGIDO | (commit A-002) | Red: `export_csv_injection_test.dart` — `=HYPERLINK`/`+SOMA`/`@`/`-` cruas na célula (aspas NÃO neutralizam fórmula). Green: `_semFormula` prefixa apóstrofo nos gatilhos `= + - @ tab CR`; 298/298 verdes |
| A-003 | 2 | CWE-755/CWE-20 | Médio | CONFIRMADO | CORRIGIDO | (commit A-003) | Red: `import_service_seguranca_test.dart` — valor string em `planejamento` lançava TypeError (fura o `on FormatException` da UI); negativo entrava cru. Green: validação `is! num` → FormatException + clamp ≥0; 302/302 verdes |
| A-004 | 3 | CWE-20 | Baixo | CONFIRMADO | CORRIGIDO | (commit A-004) | Red: `modelos_seguranca_test.dart` — peso ≤0 aceito via fromJson (envenena média ponderada); intervalo de páginas invertido/negativo gerava contagem negativa. Green: clamp peso ≥1 (Materia/Topico), páginas negativas → null, intervalo invertido → null; 309/309 verdes |
| A-005 | 3 | STRIDE-I | Baixo | CONFIRMADO | ESCALADO | – | Hive/IndexedDB sem cifra; ver Itens ESCALADO |

## Itens ESCALADO (aguardando decisão humana)

- **A-005 — Hive sem cifra em repouso (web/desktop).** Problema: dados de estudo legíveis por quem lê o perfil do SO/navegador. Dois modelos de ameaça distintos (separados após a verificação do juiz):
  - **(M1) Atacante com sessão interativa na máquina desbloqueada.** Aqui qualquer cifra com chave também local é decorativa — o atacante lê a chave junto do dado. Cifra não mitiga.
  - **(M2) Disco/backup a frio: laptop roubado/apreendido, backup exfiltrado, malware que só lê arquivos sem sessão.** Aqui uma chave derivada de PIN do usuário (não gravada em claro no disco) **mitigaria** — o dado seria ilegível sem o PIN. Este cenário NÃO é teatro; a v1 do ledger errou ao descartá-lo.
  - Opções: (a) aceitar o risco e documentar; (b) `HiveAesCipher` com chave derivada de PIN — mudança arquitetural (UX de PIN, recuperação/reset, migração de dados existentes).
  - **Recomendação: (a), por proporcionalidade aos dados, não por (M2) ser teatro.** O conteúdo é horas de estudo, notas livres e progresso — sem financeiro, saúde, credencial ou PII sensível; nunca sai do dispositivo. O custo de UX de (b) (PIN, fluxo de recuperação, risco de perda total dos dados se o usuário esquece o PIN) supera o ganho para esse tipo de dado. Decisão do dono; se o público-alvo mudar (ex.: dados sensíveis), reabrir com (b). **Escalado — não fechado unilateralmente.**

## Itens REQUER-VERIFICAÇÃO-HUMANA (fora do alcance do repo)

- **RV-001 — Painel Vercel (quando o deploy acontecer):** ativar Deployment Protection nos previews; conferir headers ativos com `curl -I https://<dominio>` e nota A em securityheaders.com; MFA na conta Vercel.

## Segredos a rotacionar

- Nenhum segredo encontrado no repositório (grep por chaves/tokens + inspeção de bordas). Nada a rotacionar.
