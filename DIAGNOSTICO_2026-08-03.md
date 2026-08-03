# Diagnóstico de estado — app_estudos

**Data:** 2026-08-03 · **Protocolo:** graph-loop (FASE 0 → 1 → 2 → 3, parada obrigatória após FASE 3)
**Método:** leitura de código + git + OSV executados de verdade. Nenhum achado sem arquivo:linha ou hash de commit.

---

## NÓ 0 — Contexto e acesso

| Campo | Valor | Evidência |
|---|---|---|
| Repositório | `app_estudos` (Flutter/Dart) | `.git` presente |
| Branch principal | `main` | `git branch -a` |
| Remote | `https://github.com/Lucasbritorj/app-estudos.git` (fetch+push) | `git remote -v` |
| Sincronia | `main` == `origin/main` @ `0c5e913` | `git status -sb` |
| Commits | **44** | `git rev-list --count --all` |
| Janela | 2026-07-10 → 2026-08-03 (24 dias corridos, 11 dias com commit) | `git log --date=short` |
| Autores | `Lucas Brito <lucasfbrito23@gmail.com>` (30) + `Lucas <mesmo e-mail>` (14) — **mesma pessoa, duas identidades git** | `git shortlog -sne` |
| Working tree | limpa (0 arquivos modificados) | `git status --porcelain` |
| Código | 120 arquivos `.dart` · 25.920 LOC em `lib/` | `find` + `wc -l` |
| Testes | 85 arquivos · 14.429 LOC · **740 declarações** `test(`/`testWidgets(` | `grep -c` |
| Dependências | 137 pacotes no `pubspec.lock` | parse do lock |

### Estrutura (profundidade 3)

```
lib/
├── application/   8 use cases (backup, apagar_dados, materia, topico, revisao, sessao, aula, notificacoes)
├── core/          notificacoes · theme · utils · widgets
├── data/          catalogo · local(hive_boxes) · models · repositories
├── domain/        24 serviços puros (stats, revisao/FSRS, prontidao, edital, banca, prova, xlsx…)
└── features/      19 telas (dashboard+widgets, caderno, simulados, edital, mapa, registro, exportar…)
test/              raiz (unit+widget) · goldens/ (19 PNG) · uat/
```

### Arquivos mais alterados (churn)

| Alterações | Arquivo |
|---|---|
| 14 | `lib/features/dashboard/dashboard_screen.dart` |
| 11 | `lib/features/dashboard/dashboard_providers.dart` |
| 9 | `LEDGER_DE_AUDITORIA.md` |
| 8 | `simulados_screen.dart` · `revisoes_screen.dart` · `domain/stats_service.dart` |
| 7 | `tiles_resumo.dart` · `hero_geral.dart` · `graficos.dart` · `revisao_service.dart` · `registro_hora.dart` · `app.dart` |

O dashboard concentra o churn: 5 dos 11 arquivos mais mexidos. Consistente com 3 redesigns registrados no histórico.

### Limite de verificação — declarado

**`flutter analyze` e `flutter test` NÃO foram executados.** O sandbox Linux tem 3,9 GB livres; o Flutter SDK 3.44.8 são 1,55 GB comprimidos (`content-length` conferido no CDN) + ~3,5 GB extraídos + artefatos de engine. Instalação inviável. Toda afirmação abaixo vem de leitura de código, git ou de ferramenta que **rodou de fato** (OSV). Onde o achado dependeria de execução, está marcado.

**O que rodou de verdade:** SCA via `api.osv.dev/v1/querybatch` sobre os 137 pacotes do `pubspec.lock` em 2026-08-03 → **0 vulnerabilidades conhecidas**.

---

## NÓ 1 — Diagnóstico

Formato: `[SEVERIDADE] Arquivo/módulo → Problema → Evidência → Impacto`

### A. Bugs e débitos técnicos

**[CRÍTICO] `lib/main.dart:10-24` → `main()` não tem nenhum tratamento de erro; falha em qualquer passo de boot impede `runApp()` → o corpo inteiro da função é uma sequência de `await` (`Hive.initFlutter`, `HiveBoxes.openAll`, `migrar`, `seedResumos`, `NotificacoesService.inicializar`, leitura de `config`) sem `try`/`catch`; `grep` por `runZonedGuarded|FlutterError.onError|ErrorWidget|PlatformDispatcher.instance.onError` em todo `lib/` retorna vazio → box Hive corrompido, IndexedDB bloqueado (Safari privado) ou cota de storage estourada produzem tela branca permanente, sem mensagem e sem caminho de recuperação. Num app local-first, a reação natural do usuário — limpar dados do site — destrói 100% do histórico. Falha de disponibilidade **e** de dados.**

**[CRÍTICO] `vercel.json` (raiz) vs `web/vercel.json` → a correção `camera=(self)` do commit `bd11b38` foi aplicada no arquivo errado; produção continua com `camera=()` → `git log -- vercel.json` mostra **um** commit (`a0c5b5a`, 24/07); `git log -- web/vercel.json` mostra `bd11b38` (03/08). Diff atual: raiz = `camera=(), microphone=()…`; `web/` = `camera=(self), microphone=()…`. E `build/web/vercel.json` existe (1.251 bytes, 03/08 09:11) — ou seja, `web/vercel.json` é copiado verbatim para o output e servido como **asset público** em `/vercel.json`, nunca lido como config (a Vercel só lê `vercel.json` na raiz do projeto) → a câmera do caderno de erros segue bloqueada no deploy. Pior: os 7 headers de segurança (HSTS, CSP, COOP, X-Frame-Options…) existem em duas cópias divergentes, e a cópia que a Vercel lê não é a que foi mantida.**

**[MÉDIO] 10 arquivos de `lib/features/` → 25 `TextEditingController` criados e nunca liberados → 58 `= TextEditingController(` no total; `.dispose()` só aparece em 6 arquivos. Sem dispose algum: `materia_dialog.dart` (6), `leituras_screen.dart` (5), `revisoes_screen.dart` (3), `topicos_screen.dart` (2), `importar_edital.dart` (2), `exportar_screen.dart` (2), `aulas_screen.dart` (2), `planejamento_screen.dart` (1), `mapa_estudos_screen.dart` (1), `ambientes_screen.dart` (1). Padrão: controllers instanciados dentro de **funções construtoras de diálogo** em `ConsumerWidget` (stateless), onde não existe `dispose()` para chamar → vazamento de `ChangeNotifier` a cada abertura de diálogo. Sessão longa com muitos cadastros acumula listeners. O padrão já foi corrigido pontualmente em `prova_screen.dart` (B11 — "controllers em Map com dispose") e não foi generalizado.**

**[MÉDIO] `android/app/build.gradle.kts:34` → build de release assinado com a chave de debug → `signingConfig = signingConfigs.getByName("debug")` sob `buildTypes { release { … } }`, com o `// TODO: Add your own signing config` do template ainda no lugar → AAB/APK de release não é publicável na Play Store e é trivialmente re-assinável. Não afeta o alvo web atual; bloqueia 100% da distribuição Android.**

**[MÉDIO] `lib/data/local/hive_boxes.dart:105-113` → escritas multi-box sem atomicidade → comentário no próprio código: *"Hive não tem transação"*; `repararOrfaos()` roda em TODO boot justamente para religar invariantes que um crash entre escritas pode quebrar → mitigado, não resolvido: o reparo é conservador (só recria revisão de aula quando **nenhuma** existe) e não cobre todos os cruzamentos entre os 16 boxes. `BackupUseCase` protege só o caminho de import/restauração.**

**[COSMÉTICO] `lib/domain/xlsx_reader.dart:252-262` → `_colunaDe` pode estourar `int` de 64 bits com ref de ~14+ letras e virar negativo → `coluna = coluna * 26 + (code - 64)` em loop sem teto; a checagem `coluna >= _maxColunas` (linha 215) não pega valor negativo → não crasha (o `while (celulas.length < coluna)` não roda com negativo), só posiciona a célula errada em silêncio. Entrada hostil já é barrada pelos tetos de bytes/linhas.**

**[COSMÉTICO] Duas identidades git para a mesma pessoa → `Lucas Brito` (30 commits) e `Lucas` (14), mesmo e-mail → `git shortlog` quebra em duas linhas; qualquer métrica por autor fica dividida. Resolve com `.mailmap`.**

### B. Segurança

**[POSITIVO — verificado] SCA limpo.** 137 pacotes consultados na OSV em 2026-08-03 → 0 vulnerabilidades conhecidas. (O `SBOM.md` do repo é de 16/07 e lista 126 pacotes — desatualizado em 11 pacotes, mas o resultado atual foi reconferido.)

**[POSITIVO — verificado] Nenhum segredo versionado.** `grep -niE "api[_-]?key|secret|password|token|BEGIN (RSA|PRIVATE)|AIza|sk-[A-Za-z0-9]"` em `lib/ web/ android/ ios/ pubspec.yaml vercel.json setup-github-deploy.ps1` → só falsos positivos semânticos ("tokens de design", "sessão-token de 1 min").

**[POSITIVO — verificado] Bordas de entrada endurecidas.** `xlsx_reader.dart` tem teto de arquivo (64 MB), teto por parte XML medido em **bytes reais inflados** (50 MB, via `Inflate.stream` com `OutputStream` limitado — não pelo header do zip), rejeição explícita de compressão não-deflate, e tetos de linha/coluna do Excel. Injeção de fórmula CSV neutralizada. Modelos com invariantes na fábrica.

**[MÉDIO] `vercel.json` duplicado divergente** — ver seção A. É o achado de segurança de configuração de maior impacto: a política que vale em produção não é a que está sendo mantida.

**[MÉDIO] `lib/main.dart` sem `runZonedGuarded`/`FlutterError.onError`** → nenhuma exceção não-tratada é capturada, registrada ou apresentada. Em release web, erro de build vira container vazio. Sem telemetria (coerente com o design offline), mas também sem tela de erro amigável.

**[BAIXO — risco já aceito formalmente] Hive sem cifra em repouso.** `HiveBoxes.openAll()` abre os 16 boxes sem `encryptionCipher`. No web = IndexedDB em claro. Aceite documentado em `c87101e` (A-005). **Condição de reabertura que agora se aplica:** o box `anexos` (`Hive.openBox<Uint8List>`) passou a guardar **fotos de enunciados** tiradas pelo usuário — o conteúdo em repouso deixou de ser só texto de estudo. Vale reavaliar o aceite com o novo escopo de dado.

**[POSITIVO] Permissões Android mínimas e coerentes.** `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`. **Sem** `SCHEDULE_EXACT_ALARM` — correto, porque `notificacoes_service.dart:66,127` usa `AndroidScheduleMode.inexactAllowWhileIdle`. Sem permissão de CAMERA declarada, o que é o comportamento certo para `image_picker` via intent do sistema.

### C. Arquitetura e estrutura

**[POSITIVO — verificado] Camadas respeitadas, sem exceção.** Quatro greps de violação, todos vazios:
- `lib/domain/*.dart` não importa `flutter/material`, `flutter/widgets`, `riverpod` nem `features/`
- `lib/application/*.dart` não importa `features/`
- `lib/data/**` não importa `features/`
- nenhum `features/X` importa `features/Y`

Domínio 100% puro e testável. Isto é raro e é o maior ativo estrutural do projeto.

**[MÉDIO] `lib/features/caderno/caderno_screen.dart` → 1.420 LOC com 17 classes num arquivo → `_CadernoScreenState`, `_AbaFila`, `_CartaoFila(+State)`, `_LinhaResposta`, `_FotoEnunciado`, `_AbaTodas(+State)`, `_AvisoOrfas`, `_LinhaQuestao`, `_AbaEstatisticas`, `_NumeroResumo`, `_LinhaEstatistica`, `_BarraForecast`, `_DialogoQuestao(+State)` → navegação e revisão custosas; o arquivo é 2,3× o segundo maior. Sem defeito funcional associado.**

**[MÉDIO] `lib/features/dashboard/dashboard_providers.dart` → 27 providers em 679 LOC → `grep -c '^final .*Provider'` = 27 → ponto único de conflito de merge e de leitura para toda a feature mais mexida do repo (11 alterações). `Provider` do Riverpod cacheia, então não há custo de performance — é dívida de organização.**

**[BAIXO] 13 arquivos acima de 500 LOC** — `caderno_screen` 1420, `prova_screen` 810, `dashboard_providers` 679, `simulados_screen` 638, `mapa_estudos_screen` 627, `registro_form` 625, `exportar_screen` 611, `planilha_import_service` 550, `graficos` 537, `stats_service` 529, `repositorios` 524, `edital_screen` 506, `app.dart` 501.

**[MÉDIO] Documentação diverge do repositório em 3 pontos verificáveis:**

| Doc | Afirma | Realidade | Comando |
|---|---|---|---|
| `ROADMAP.md:5-8` | "o repositório não tem `git remote`" / "Bloqueado por credenciais" | remote `origin` configurado, `main` == `origin/main` | `git remote -v` |
| `ROADMAP.md:3` | "histórico em **9 commits**" | 44 commits | `git rev-list --count --all` |
| `README.md:22` | "621 testes" | 740 declarações | `grep -c` |
| `README.md:36-40` | "`git status` mostra ~200 arquivos modified (ruído CRLF)" | working tree limpa — `.gitattributes` resolveu | `git status --porcelain` |
| `SBOM.md` | 126 pacotes (16/07) | 137 pacotes | parse do `pubspec.lock` |

Efeito prático: o "Curto prazo" do ROADMAP (item 1 — fazer o push) **já foi feito**, e o item 2 (redeploy) está descrito como suficiente quando na verdade não corrige nada, porque o arquivo corrigido não é o que a Vercel lê.

**[BAIXO — operacional] `.git/index.lock` presente agora (0 bytes, 03/08 15:11).** Bloqueia o próximo `git commit`. O ROADMAP registra uma ocorrência anterior idêntica (lock órfão de 29/07 que travou commits por dias). Ressalva de honestidade: **este lock específico foi criado pelos `git status` desta análise** sobre o mount Windows, que negou o `unlink` de volta (`warning: unable to unlink … Operation not permitted`). Precisa ser apagado à mão. O padrão recorrente é o achado real.

### D. Experiência do usuário

**[CRÍTICO] Falha de boot → tela branca silenciosa** — ver A. É o pior caminho de UX do app: sem texto, sem botão, sem log visível.

**[CRÍTICO] Foto do enunciado quebrada em produção** — o botão "Câmera" aparece no navegador mobile (`defaultTargetPlatform` = android/iOS) e o `getUserMedia` é negado pela `Permissions-Policy` do deploy. Diagnóstico correto no commit `bd11b38`, correção no arquivo errado.

**[POSITIVO — verificado] Estados vazios e responsividade tratados.** `EstadoVazio` usado em 10 arquivos, `ConteudoCentral` em 20 (das 19 features), 13 arquivos com indicador de progresso, breakpoint de sidebar em `app.dart:76` (`_larguraSidebar = 1080.0`).

**[MÉDIO] Acessibilidade cobre o dashboard e mais nada.** 21 `Semantics(` em todo o `lib/`, dos quais **17 estão em `features/dashboard/`** — os 4 restantes são `edital_screen` (2), `mapa_estudos_screen` (1) e `caderno_screen` (1). Telas acima de 200 LOC com **zero** `Semantics`: `prova_screen` (810), `simulados_screen` (638), `exportar_screen` (611), `leituras_screen` (460), `revisoes_screen` (370), `topicos_screen` (353), `planejamento_screen` (355), `configuracoes_screen` (343), `resumos_screen` (324), `busca_screen` (304), `cronometro_screen` (271), `aulas_screen` (267), `questoes_orfas_screen` (244), `ambientes_screen` (228), `onboarding_screen` (220). O trabalho de a11y (Q2, B18) foi real, mas parou no dashboard — e é justamente a prova cronometrada, o registro e o cronômetro que o usuário opera sob pressão.

**[BAIXO] `B16` — prova cronometrada em andamento fora do backup.** Deliberado (estado preso ao relógio local), mas trocar de aparelho no meio de um simulado perde a folha de respostas sem aviso prévio.

### E. Design/UI

**[POSITIVO — verificado] Design system tokenizado de verdade.** `lib/core/theme/app_theme.dart` expõe `Spacing` (xs/sm/md/lg/xl/xxl), `Radii`, `LuminaColors`, `StatusColors`, `LuminaElevation`, `LuminaText`, `VizColors`, mais os componentes `ConteudoCentral`, `LuminaBackground`. Fonte de marca (Space Grotesk variável) como asset local — deliberadamente fora de CDN para não mexer na CSP calibrada para CanvasKit.

**[POSITIVO] Componentização contra cópia-e-cola** — `AvatarCor` e `StatusColors.porTaxa` extraídos em `fe31c77` com a mensagem "fim das cópias".

**[MÉDIO] Sem tema claro (`Q3`).** `app.dart:57` passa só `theme: buildDarkTheme()`; não há `darkTheme`, `themeMode` nem `buildLightTheme` em lugar nenhum. Dark-only. Como o Lumina já é tokenizado, é trabalho de paleta, não refatoração — mas hoje o app ignora a preferência de sistema do usuário.

**[BAIXO] Cobertura visual quase completa.** 19 goldens em `test/goldens/`, faltando só `onboarding` (fluxo multi-passo). Rodam em job de CI separado com `continue-on-error` — decisão correta, diferença de pixel por fonte/plataforma não deve bloquear merge.

---

## NÓ 2 — Linha do tempo real (entregas, não intenções)

### Início — 10/07 a 16/07 · 5 commits (11%)

| Commit | Entrega concreta |
|---|---|
| `7b1fb55` | Base do app: ambientes, dashboard consolidado, simulados, sidebar |
| `cc6693e` | Parser de edital, dashboard em 2 colunas, sessões de leitura |
| `b24d32a` | 366 frases motivacionais (uma por dia do ano) |
| `1a98701` | Assets do design system + dependências |
| `0e8e8e6` | **Camada `application/`, integridade referencial, Elo unificado** — o commit que fixa a arquitetura em camadas que se sustenta até hoje |

Duas sessões grandes ("big bang" inicial) e um refactor arquitetural. Sem testes formais neste bloco.

### Meio — 16/07 a 24/07 · 28 commits (64%)

Onde o projeto virou produto. Quatro correntes paralelas:

**Segurança (auditoria autônoma, 9 commits, 16-17/07)** — `14dd781` preparação de deploy + ledger · `c40e8ec`/`9f68e2c`/`d42bb1c`/`fabf186` A-001 XlsxReader em 4 iterações (teto → bytes reais → `Inflate` direto p/ limitar pico na web → rejeição de não-deflate) · `0501500` A-002 injeção de fórmula CSV · `7f6a67e` A-003 backup hostil vira `FormatException` · `55604ba` A-004 invariantes de modelo · `c87101e` A-005 aceite formal de risco.

**Motor e dados (18-20/07)** — `d8d056d` `atualizadoEm` + tombstones (preparo de sync) · `d499967` export modelo estrela p/ Power BI (fato + dimensões + calendário, zipado) · `c7cab31` FSRS responde à taxa real de acerto · `0fba400` true retention + forecast.

**Design (18-24/07)** — `fd6eeb0` branding PWA · `8e8bf17` `ConteudoCentral` em 7 telas · `fe31c77` extração de componentes · `9ad9584` heatmap de constância · `c8cd181` hierarquia em 3 colunas · `55cc526` Space Grotesk + tokens · `b85a488` redesign do dashboard · `f03ae5b` masonry + `EstadoVazio` · `9399268` MoM/YoY, wipe out, sidebar colapsável.

**Qualidade (22-24/07)** — `4cce166` e `50b6db7` WCAG 2.2 AA · `3488c69` resiliência de persistência (isola erro por registro) · `a0c5b5a` correções da auditoria de 24/07 · `6cbca86` goldens sob tag `screenshots` · `83dfd1b` **dois bugs achados testando com dataset de 2.000h** — teste de carga real gerando achado real.

### Atual — 27/07 a 03/08 · 11 commits (25%)

| Data | Commit | Entrega |
|---|---|---|
| 27/07 | `d9aa734` | Fecha 4 achados abertos da auditoria + golden determinístico |
| 31/07 | `6cf5383` | **CI GitHub Actions** — `flutter analyze` + `flutter test --exclude-tags screenshots`; Flutter fixado em 3.44.8; job `goldens` separado com `continue-on-error`; `dart format` deliberadamente fora do gate, com o motivo documentado no YAML |
| 31/07 | `f083c13` | **4 domínios novos**: caderno de erros, banca, edital verticalizado, prova cronometrada |
| 31/07 | `00eb60a` | Telas de caderno/edital/prova/busca + acessibilidade |
| 03/08 | `b5199c6` | `_aplicarColado` monta o lote sobre o estado atual, não sobre a cópia do build |
| 03/08 | `99d18d6` + `aae491c` | Goldens de 6 → 9 → **19 telas** |
| 03/08 | `bd11b38` | Permissions-Policy + manifesto PWA — **corrigido no arquivo que a Vercel não lê** |
| 03/08 | `4417f93` + `0c5e913` | Atualizações do ROADMAP |

Observação de processo digna de registro: 86 arquivos sem commit foram reorganizados em 6 commits temáticos, e **cada commit de código foi extraído para árvore limpa (`git archive`) e teve `flutter analyze` rodado isoladamente** — o primeiro corte de C2 não compilava (testes de domínio importando providers de UI) e o histórico foi refeito antes da publicação. Isso é disciplina acima da média.

### Leitura da curva

- **Volume:** 25.920 LOC de produção + 14.429 de teste em 24 dias. Razão teste/produção = **0,56**, alta.
- **Natureza:** de 20/07 em diante, correções passam a vir de **execução** (dataset de 2.000h, UAT, goldens), não de leitura. É a inflexão de qualidade do projeto.
- **Padrão de falha recorrente:** as duas features quebradas do bloco Atual (`b5199c6` gabarito colado sobre cópia do build; `bd11b38` camera no arquivo errado) são do mesmo tipo — **feature correta isolada, quebrada no cruzamento com outra**. O próprio ROADMAP nomeia isso: *"duas features corretas isoladamente, quebradas no cruzamento"*. A suíte, sendo unit + widget isolado, é estruturalmente cega para essa classe (é exatamente o que `Q9 — integration_test` cobriria).

---

## NÓ 3 — Priorização

Pesos: Segurança/dados **40** · Bugs que impedem uso core **30** · Dívida estrutural que bloqueia evolução **20** · UX/Design de alto impacto **10**.

| # | Ação | P | Esf. | Score | Dependências | Resultado esperado (mensurável) |
|---|---|---|---|---|---|---|
| 1 | **Blindar `main()`**: envolver o boot em `try`/`catch` + `runZonedGuarded`, e `runApp` de uma tela de falha com o erro, botão "tentar de novo" e botão "exportar dados brutos" antes de qualquer sugestão de limpar storage | P0 | M | 68 | nenhuma | Teste que injeta exceção em `HiveBoxes.openAll()` e afirma tela de erro renderizada, nunca tela branca. Zero caminho de boot que termine sem `runApp()` |
| 2 | **Unificar `vercel.json`**: apagar `web/vercel.json` (é asset público, não config), levar `camera=(self)` para o `vercel.json` da raiz, redeployar | P0 | S | 58 | nenhuma | `curl -sI https://<dominio> \| grep -i permissions-policy` devolve `camera=(self)`; `curl -s https://<dominio>/vercel.json` devolve 404; exatamente 1 `vercel.json` no repo |
| 3 | **Teste de fumaça pós-deploy no CI**: job que faz `curl -I` no domínio e falha se qualquer um dos 7 headers divergir do esperado | P0 | S | 44 | #2 | Nenhuma regressão de header chega a produção sem build vermelho. Fecha a classe de falha de #2, não só a instância |
| 4 | **Signing config de release Android**: keystore própria, `key.properties` no `.gitignore`, `signingConfigs.create("release")` | P1 | S | 38 | nenhuma | `flutter build appbundle --release` produz AAB assinado com chave de produção; `apksigner verify --print-certs` não mostra `CN=Android Debug` |
| 5 | **Handler global de erro de UI**: `FlutterError.onError` + `ErrorWidget.builder` com card legível em vez do container vazio do release web | P1 | S | 37 | #1 | Widget test que lança em `build()` e afirma o card de erro; nenhum erro de UI resulta em área em branco |
| 6 | **Liberar os 25 `TextEditingController`**: converter os 10 diálogos para `StatefulWidget`/hook com `dispose()`, ou usar `restorationId`+`TextEditingController` de escopo | P1 | M | 27 | nenhuma | `grep -c '= TextEditingController('` == soma dos `dispose()` correspondentes nos 10 arquivos; suíte roda com `LeakTesting` ligado sem vazamento reportado |
| 7 | **Atomicidade multi-box**: generalizar o snapshot do `BackupUseCase` para toda escrita que toca ≥2 boxes (exclusão em cascata de matéria/tópico, conclusão de aula) | P1 | M | 28 | nenhuma | Teste que mata a escrita entre o box 1 e o box 2 e afirma estado íntegro após o boot seguinte. Também entrega o `Q5 — desfazer` de graça |
| 8 | **`integration_test` ponta a ponta** cobrindo os 3 fluxos de cruzamento: registrar sessão → revisão gerada → concluir; importar planilha → dashboard; iniciar prova → colar gabarito → corrigir | P1 | M | 24 | nenhuma | 3 testes de integração verdes no CI. Fecha a classe de defeito que produziu `b5199c6` e `bd11b38` |
| 9 | **Sincronizar docs com o repo**: `ROADMAP.md` (remote existe, 44 commits, push feito), `README.md` (740 testes, sem ruído CRLF), regerar `SBOM.md` (137 pacotes) | P2 | S | 14 | #2 | Zero afirmação verificável falsa nos 3 arquivos. Sugestão: gerar a contagem por script no CI em vez de escrever à mão |
| 10 | **Semantics nas 15 telas descobertas**, priorizando `prova_screen`, `registro_form` e `cronometro_screen` (operadas sob pressão de tempo) | P2 | L | 14 | nenhuma | `Semantics(` presente em toda tela >200 LOC; teste de a11y por tela nos moldes do `acessibilidade_test.dart` atual |
| 11 | **`B16` — prova em andamento no backup**, ou aviso explícito de perda na tela de exportação | P2 | M | 16 | #7 | Trocar de aparelho no meio da prova preserva a folha de respostas, ou o usuário é avisado antes de exportar |
| 12 | **Tema claro (`Q3`)** — `buildLightTheme()` sobre os tokens existentes + `themeMode: ThemeMode.system` | P3 | M | 7 | nenhuma | Golden de 19 telas nas duas paletas sem quebra de contraste; WCAG AA mantido nas duas |

### Fora do corte (registrados, não priorizados)

`caderno_screen.dart` 1.420 LOC e `dashboard_providers.dart` 27 providers — dívida de organização, sem defeito associado. Quebrar quando houver mudança funcional na área, não como tarefa própria. `_colunaDe` com overflow silencioso e as duas identidades git (`.mailmap`) — cosméticos.

### Nota sobre a sequência

Itens 1 e 2 são independentes e cabem no mesmo dia. Item 3 é o que impede a repetição do 2 e vale mais que o próprio 2 no médio prazo. Item 8 é o único que ataca a **causa** do padrão "feature correta isolada, quebrada no cruzamento" — se houver orçamento para uma coisa estrutural só, é essa.

---

**PARADA — fim da FASE 3.** Sem planejamento de execução, sem alteração de código.
