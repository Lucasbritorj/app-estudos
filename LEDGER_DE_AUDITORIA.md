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

1. **A-001** — XlsxReader: exaustão de memória por refs `r` sem teto (CWE-400/CWE-1284, STRIDE-D). Arquivo hostil trava/derruba o app. **Alto**
2. **A-002** — ExportService: CSV/formula injection (CWE-1236, OWASP A03-adjacent). Dado vindo de xlsx/edital de terceiro executa fórmula no Excel da vítima. **Médio**
3. **A-003** — ImportService: `(v as num)` em `planejamento` lança TypeError que fura o `on FormatException` da UI (CWE-755/CWE-20). **Médio**
4. **A-004** — Modelos: `peso`/`corSlot`/páginas sem clamp no `fromJson` (integridade; `corDaSerie` usa `%`, sem crash). **Baixo**
5. **A-005** — Hive web sem cifra em repouso (Information Disclosure local). Decisão de produto (chave local não protege contra o mesmo atacante). **ESCALAR**

## Registro de achados

| ID | Fase | Classe | Severidade | Conf. | Estado | Commit | Evidência (Red → Green) |
|---|---|---|---|---|---|---|---|
| A-001 | 2 | CWE-400/CWE-1284, STRIDE-D | Alto | CONFIRMADO | CORRIGIDO | (commit A-001) | Red: `xlsx_reader_seguranca_test.dart` — parser devolveu 2M linhas / 18.278 células ditadas por `r` hostil. Green: tetos `_maxLinhas`/`_maxColunas`/`_maxBytesParteXml` + FormatException; 296/296 verdes (293 baseline + 3 novos) |
| A-002 | 2 | CWE-1236 | Médio | CONFIRMADO | ABERTO | – | `export_service.dart:_campo/_campoBi` não neutralizam `=`,`+`,`-`,`@` |
| A-003 | 2 | CWE-755/CWE-20 | Médio | CONFIRMADO | ABERTO | – | `import_service.dart:90` `(v as num)` fora do wrapper; UI captura só FormatException (`exportar_screen.dart:367,437`) |
| A-004 | 3 | CWE-20 | Baixo | CONFIRMADO | ABERTO | – | `materia.dart:95-98` sem clamp de `peso`; páginas negativas em `registro_hora.dart:157-158` |
| A-005 | 3 | STRIDE-I | Baixo | CONFIRMADO | ESCALADO | – | Hive/IndexedDB sem cifra; ver Itens ESCALADO |

## Itens ESCALADO (aguardando decisão humana)

- **A-005 — Hive sem cifra em repouso (web/desktop).** Problema: dados de estudo legíveis por quem tem acesso ao perfil do SO/navegador. Opções: (a) aceitar o risco e documentar (app local-first single-user, cifra com chave armazenada localmente não resiste ao mesmo atacante — segurança teatral); (b) `HiveAesCipher` com chave derivada de PIN do usuário — mudança arquitetural (UX de PIN, recuperação, migração de dados). **Recomendação: (a)** — o modelo de ameaça real (atacante com acesso ao perfil local) já implica comprometimento total da máquina; documentar no README. Dado não é sensível (horas de estudo), LGPD-wise é dado pessoal trivial local que nunca sai do dispositivo.

## Itens REQUER-VERIFICAÇÃO-HUMANA (fora do alcance do repo)

- **RV-001 — Painel Vercel (quando o deploy acontecer):** ativar Deployment Protection nos previews; conferir headers ativos com `curl -I https://<dominio>` e nota A em securityheaders.com; MFA na conta Vercel.

## Segredos a rotacionar

- Nenhum segredo encontrado no repositório (grep por chaves/tokens + inspeção de bordas). Nada a rotacionar.
