# Entregas até 03/08/2026 — registro das ondas concluídas

Extraído de `ROADMAP.md` em 10/08/2026, quando o roadmap foi reescrito como
fonte de verdade do estado presente. É registro do que foi entregue e onde —
não descreve trabalho pendente. Estado atual: [`../../ROADMAP.md`](../../ROADMAP.md).

Contexto original do cabeçalho: estado de 03/08/2026, 740 testes verdes
(721 na suíte padrão + 19 goldens), `flutter analyze` limpo.

---

## 1. Concluído nesta rodada

### Fase 1 — CI e segurança de dados

| # | Entrega | Onde |
|---|---|---|
| Q1 | **CI GitHub Actions**: `flutter analyze` + `flutter test --exclude-tags screenshots` a cada push/PR; job `goldens` separado com `continue-on-error` e upload de `test/failures/`. Versão do Flutter fixada em 3.44.8 (canal flutuante quebraria o build sozinho). | `.github/workflows/ci.yml` |
| B1 | **`minutosPadraoRevisao` na UI**: dropdown 0/5/10/15/20/30 min, com o texto dizendo que é ESTIMATIVA e que soma no total de horas sem ter sido cronometrado. "Não creditar" volta ao comportamento antigo. | `configuracoes_screen.dart` |
| B2 | **`Configuracoes` no backup**: campo tolerante em `jsonCompleto`/`parseBackup` (versão 1 preservada). Backup antigo sem a chave devolve `null` e NÃO zera as preferências de quem restaura. Configuração corrompida vira `FormatException`, não `TypeError`. | `export_service.dart`, `import_service.dart` |
| B3 | **`cancelarTodas`** nas notificações, chamado no wipe e após restaurar backup (as revisões restauradas têm ids novos; os lembretes antigos ficariam órfãos no sistema operacional). | `notificacoes_service.dart`, `apagar_dados_use_case.dart` |
| B4 | **Rollback de importação**: novo `BackupUseCase` serializa o estado ANTES de escrever; falha no meio reaplica o snapshot e repropaga o erro; snackbar com **"Desfazer"** por 10 s. Backup parcial (de ambiente) é recusado no use case, não só na tela. | `application/backup_use_case.dart`, box `HiveBoxes.rollback` |

### Fase 2 — arestas críticas

| # | Entrega |
|---|---|
| B12 | Gabarito digitado persiste no Hive item a item; reabrir a prova volta com tudo preenchido. Colar gabarito em lote grava num único `atualizar()`. |
| B9 | `QuestaoErrada.copyWith(limparAno:)` — mesma convenção de `Materia.limparMinutosAlvo`. Campo vazio apaga o ano. |
| B10 | Pluralização no resultado da prova via helper `plural()`, cobrindo acertos, erros, em branco e sem gabarito. |
| B11 | Correção da prova em `ListView.builder`; controllers em `Map` com `dispose`. |
| B8 | Aba Estatísticas do caderno expõe **por banca** e **por tópico** (total / ativas / dominadas / taxa ao refazer). |
| B7 | Aviso na exportação: prova cronometrada em andamento não entra no backup; fotos aumentam o arquivo. |
| B5 | Tela **Questões órfãs**: detecta questão cuja matéria/tópico não existe mais e permite **reatribuir** (nunca excluir). Aviso na aba "Todas". |
| B6 | Ação **Mover** no menu do tópico, com `TopicoUseCase.podeMoverPara` bloqueando ciclo (si mesmo, filho, neto, outra matéria). Destino inválido fica desabilitado com o motivo. Antes, mudar de pai exigia excluir e recriar — e a cascata levava as revisões pendentes junto. |

### Fase 3 — acessibilidade e produtividade

| # | Entrega |
|---|---|
| Q2 | `Semantics` em KPIs (valor por extenso: "1 hora e 35 minutos"), gráficos (resumo textual do dado + `excludeSemantics`), FAB, chama do streak e linhas de status. Descoberto no caminho: os 3 `Semantics` que já existiam nos gráficos vazavam os `Text` internos por falta de `excludeSemantics`. |
| Q4 | **Busca global** (`BuscaService` puro + tela): matérias, tópicos, questões, resumos, aulas e simulados; sem acento, case-insensitive, ranking prefixo > palavra > substring no título > corpo; termo com menos de 2 caracteres devolve vazio; entrada hostil (`.*`, ReDoS, emoji, 500 mil caracteres) não lança. Lupa no AppBar do dashboard + item na sidebar e em "Mais". |
| F1 | **Foto do enunciado** no caderno: `image_picker 1.2.3`, compressão obrigatória (`maxWidth: 1600`, `imageQuality: 70`), bytes num box separado (`HiveBoxes.anexos`) — a lista de questões é relida a cada rebuild e carregaria megabytes à toa. Entram no backup em base64 e no snapshot de rollback. Botão de câmera só em plataforma que tem câmera. |

### Evidência de execução

```
flutter analyze --no-pub
Analyzing app...
No issues found! (ran in 1.7s)

flutter test (em 3 lotes, limite de tempo por chamada)
00:36 +229: All tests passed!
00:16 +167: All tests passed!
00:29 +314: All tests passed!

flutter test test/screenshots_test.dart --tags screenshots
00:05 +6: All tests passed!
```
Total: **710 + 6 = 716** (baseline da rodada anterior: 621).
Diff: 42 arquivos alterados, +1.574/−251, mais 30 arquivos novos.

---

## 1b. Rodada de 31/07 — débito de curto prazo liquidado

| # | Entrega | Prova |
|---|---|---|
| Q8 | **`dart format` removido do gate do CI**, com o motivo documentado no `ci.yml`. Não era largura: é short style (formatter pré-Dart 3.7) contra tall style (SDK 3.12.2). Reformatar mexeria em 109 dos 204 arquivos (8.024 linhas) e — medido — o próprio formatter introduz 2 lints de `curly_braces_in_flow_control_structures`, sujando o `flutter analyze`. | medição no terminal |
| B13 | `podeMoverPara` movido de `Topico` para **`TopicoUseCase`**: a resposta depende da COLEÇÃO, não de um tópico isolado — é regra de aplicação, não invariante de modelo. 4 chamadas na tela e 12 no teste atualizadas. | 32 testes verdes |
| B14 | Pluralização do simulado corrigida. O helper virou **`plural()` compartilhado** em `core/utils/formatters.dart`; `prova_screen.dart` deixou de ter a cópia privada. | 46 testes verdes |
| B15 | **`ExecucaoProvaController.mutar`**: aplica a mutação sobre o estado ATUAL em vez da cópia capturada no build. Vale para gabarito E marcação de resposta. | 5 testes novos, incluindo contraprova que documenta o defeito |
| B17 | Indicador de foto na aba Todas do caderno, lendo só a flag `temAnexo` (nunca os bytes — ler o box por linha derrubaria a rolagem), com rótulo semântico próprio. | teste de widget |
| B18 | Vazamento semântico corrigido em `card_diagnostico`, `card_bancas`, `card_caderno_erros`, `card_true_retention`, `card_edital`. Em `card_diagnostico` o `excludeSemantics` ficou restrito à linha do título: aplicá-lo ao card inteiro apagaria mensagem e evidências da árvore de acessibilidade — regressão pior que o bug. | 5 testes + 6 goldens sem diff de pixel |

## 1c. Rodada de 03/08 — versionamento, cobertura visual e PWA

| # | Entrega | Prova |
|---|---|---|
| — | **86 arquivos sem commit** viraram 6 commits temáticos. Um `index.lock` órfão de 29/07 travava QUALQUER commit no repositório — inclusive os seus. Removido. | `git log` |
| — | Cada commit de código foi extraído para uma árvore limpa (`git archive`) e teve `flutter analyze` rodado isoladamente. O primeiro corte de C2 não compilava (dois testes de domínio importavam providers de UI); histórico refeito antes de qualquer publicação. | analyze limpo em `f083c13` e `00eb60a` |
| B19 | `_aplicarColado` monta o lote dentro de `mutar`, sobre o estado atual. | 42 testes verdes |
| Q6 | Goldens de **6 para 9**: correção de prova, questões órfãs e busca. | determinismo provado com 2 comparações seguidas |
| F9 | `camera=(self)` na Permissions-Policy e manifesto completo. | JSON validado, analyze limpo |

**Achado da rodada:** a `Permissions-Policy` do deploy trazia `camera=()`,
escrita quando o app não tinha câmera. A foto do enunciado (F1) usa
`image_picker`, e no navegador de celular `defaultTargetPlatform` é
android/iOS — o botão "Câmera" aparecia e o `getUserMedia` era bloqueado.
Duas features corretas isoladamente, quebradas no cruzamento.

**Correção de rumo:** "F9 — PWA instalável" estava superestimado no roadmap.
Manifesto, ícones 192/512 com maskable, `apple-touch-icon` e meta tags de iOS
já existiam. O valor da etapa foi achar o bloqueio da câmera, não o PWA.

