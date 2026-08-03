# Roadmap — app_estudos

Estado em 03/08/2026, verificado por execução: **730 testes verdes**
(721 na suíte padrão + 9 goldens), `flutter analyze` limpo, CI configurado,
**histórico commitado em 6 commits** que compilam isoladamente.

Legenda de esforço: **P** = até meio dia · **M** = 1-3 dias · **G** = 1-2 semanas.

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

## 2. Bugs abertos

| # | Problema | Onde | Esforço |
|---|---|---|---|
| B16 | Prova em andamento continua fora do backup (deliberado — estado preso ao relógio local), mas não há como exportá-la nem avisá-la ao trocar de aparelho. | `export_service.dart` | M |
| B20 | Fase de **execução** da prova não tem golden: o cronômetro lê `DateTime.now()` a cada segundo e mantém `Timer.periodic` vivo. Capturar exige injetar o relógio na tela (hoje só o `hojeProvider` é injetável). | `prova_screen.dart` | M |

## 3. Qualidade e infraestrutura

| # | Lacuna | Esforço |
|---|---|---|
| Q3 | **Sem tema claro** (dark-only, sem `ThemeMode`). O Lumina já é tokenizado: é trabalho de paleta, não refatoração. | M |
| Q5 | **Sem desfazer** fora da importação. Excluir matéria/tópico/questão continua irreversível com só um diálogo. Agora que `BackupUseCase` existe, dá para generalizar o padrão de snapshot. | M |
| Q6 | Goldens cobrem 9 telas de ~19 (faltam aulas, leituras, planejamento, mapa, ambientes, resumos, cronômetro, onboarding, configurações). | P |
| Q9 | Sem teste de integração ponta a ponta (`integration_test`) — a suíte é unit + widget isolado. | M |

## 4. Funcionalidades sugeridas

| # | Funcionalidade | Racional | Esforço |
|---|---|---|---|
| F2 | **Importar questões em lote** (CSV/planilha) | Quem já mantém caderno no Excel migra sem redigitar. `xlsx_reader` já existe. | M |
| F3 | **Relatório PDF semanal automático** | O gerador de PDF já existe; falta o recorte semanal e o agendamento. | P |
| F4 | **Cronograma dia-a-dia até a prova** | A prontidão já projeta o domínio na data e o edital já mede cobertura — falta virar plano executável. Peça que amarra planejamento, edital e revisão. | G |
| F5 | **Exportar caderno para Anki** | Boa parte dos concurseiros já vive no Anki; exportar em vez de competir aumenta adoção. | M |
| F6 | **Notificação acionável** ("Acertei"/"Errei" direto do lembrete) | Revisão feita no semáforo é revisão feita. `flutter_local_notifications` já suporta actions. | M |
| F7 | **Nota de corte** vs prontidão projetada | Transforma "70% de prontidão" em "acima/abaixo do corte do ano passado". | M |
| F8 | **Backup automático agendado** | Hoje depende de o usuário lembrar. O `BackupUseCase` já sabe serializar tudo. | M |
| F9 | **PWA instalável** (ícone, splash) | O app já é publicado na web e é local-first; falta o manifesto completo. | P |
| F10 | **Lei seca / artigo lido** | Direito se estuda por artigo. Encaixa no modelo de Leituras. | M |
| F11 | **Sincronização multi-dispositivo** | `atualizadoEm` e tombstones já preparam isso. Falta o transporte — e a decisão de produto (servidor, custo, privacidade) que quebra o "100% offline". | G |
| F12 | **Ciclo de estudos rotativo clássico** | O app tem ciclo por utilidade (Elo/peso); o rodízio tradicional é o que muita gente espera encontrar. | M |

---

## 5. Planejamento

### Curto prazo — 1 a 2 semanas
Tema: publicar e fechar a cobertura visual.

1. **Configurar `git remote` e fazer o primeiro push.** Hoje o repositório é só
   local: sem remote, o CI nunca rodou no runner do GitHub e o trabalho existe
   num único disco. É o item de maior risco em aberto.
2. **Redeploy da web** para a `Permissions-Policy` nova valer — sem isso a
   câmera do caderno de erros segue bloqueada em produção.
3. **Q6** — goldens das 10 telas restantes.
4. **B20** — injetar o relógio na `ProvaScreen` para capturar a fase de execução.

### Médio prazo — 1 a 2 meses
Tema: reduzir atrito e fechar o ciclo de uso diário.

1. **F2 — importar questões em lote** e **F3 — PDF semanal**.
2. **Q3 — tema claro**.
3. **Q5 — desfazer** generalizado, reusando o padrão de snapshot do `BackupUseCase`.
4. **F8 — backup automático** e **F6 — notificação acionável**.
5. **Q9 — teste de integração** ponta a ponta.

### Longo prazo — 3 a 6 meses
Tema: o que muda a natureza do produto.

1. **F4 — cronograma dia-a-dia até a prova** (consome prontidão + cobertura do edital + horas disponíveis).
2. **F7 — nota de corte** como referência.
3. **F5 — Anki** e **F10 — lei seca**.
4. **F12 — ciclo rotativo**.
5. **F11 — sincronização multi-dispositivo**, por último: é o único item que quebra a premissa "100% offline" e exige decisão de produto antes de decisão técnica.

---

## 6. Se houver pouco tempo

**Primeiro push com CI ligado**, **F9 (PWA)** e **F3 (PDF semanal)**.
O primeiro prova a rede de proteção no runner real; os outros dois entregam valor
visível em meio dia cada, aproveitando código que já existe.
