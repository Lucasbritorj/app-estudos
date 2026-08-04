# NÓ 5 — Plano da onda P1 revisada

Base: `ef14dd2` + working tree com heroTag (9 arquivos) e 2 testes novos.
**Planejado, não executado.** Nenhuma linha alterada por este documento.

---

## FASE 0 — Contexto

| Campo | Valor |
|---|---|
| Repo | `/app_estudos`, `main` == `origin/main` @ `ef14dd2` |
| Working tree | 10 modificados (heroTag + README), 2 testes novos — **não commitados** |
| Verificação neste sandbox | Dart SDK 3.12.2 + fonte do Flutter 3.44.8 reinstalados. Gate = parse + conferência de API. `flutter analyze`/`test` continuam sendo seus |

### Arquivos-chave por item

| # | Item | Arquivos |
|---|---|---|
| 1 | Piso 15 min (M-08) | `domain/stats_service.dart:194-215` · `domain/diagnostico_service.dart:23-26` · `domain/quests_service.dart:47-72` · `features/dashboard/widgets/heatmap_constancia.dart:18-24` |
| 2 | Cascata de aula (D-04) | `application/materia_use_case.dart:16-33` · `test/materia_cascata_test.dart` |
| 3 | Card "Plano de hoje" | `widgets/hero_missao_hoje.dart` · `card_melhorar_hoje.dart` · `card_quests.dart` · `card_plano.dart` · `dashboard_screen.dart:135-152` |
| 4 | Revisões concluíveis no dashboard | `application/revisao_use_case.dart:34-39` · `features/revisoes/revisoes_screen.dart` · novo card + `dashboard_providers.dart` |
| 5 | pt-BR | `core/utils/formatters.dart:12-18` · `features/exportar/exportar_screen.dart:99` |

---

## Pushback antes do plano: 2 dos 5 itens estão quase prontos

**Item 2 já está implementado no caminho direto.** `AulaUseCase.excluirEmCascata` existe (`aula_use_case.dart:25-47`), está ligado em `aulas_screen.dart:240`, e tem teste dedicado (`test/aula_cascata_test.dart`). Sobra **um** furo, e é real — descrito abaixo.

**Item 5 está ~90% pronto.** Os date pickers já são pt-BR desde o U-12: `app.dart:60-66` tem os 3 delegates (`GlobalMaterial/Widgets/CupertinoLocalizations`) + `locale: Locale('pt','BR')` + `supportedLocales`. E `formatarDecimal` (`formatters.dart:15`) já troca ponto por vírgula, usado em 16 pontos. `grep` por `toStringAsFixed([12])` sem `replaceAll` em `lib/features` e `lib/domain` retorna **exatamente 1 linha**.

Manter os 5 na ordem pedida — só encolhendo 2 e 5 para o que de fato falta. Escopo honesto vale mais que ordem cumprida.

---

## ITEM 1 — Piso de 15 min consistente (M-08)

### Diagnóstico

O piso existe e funciona **no streak**:

```dart
// stats_service.dart:200
static const pisoMinutosStreak = 15;

// stats_service.dart:204-215
static Set<DateTime> _diasComEstudoReal(List<RegistroHora> registros) {
  ...
  if (e.value >= pisoMinutosStreak) e.key,
}
```

Usado em `streakDetalhado`, `streakPico`, `streakPicoComCongelamento`, `diasCongeladosDoStreak` (linhas 221, 255, 325).

**Duas superfícies contradizem esse piso no mesmo dashboard:**

| Onde | Código | Comportamento com dia de 5 min |
|---|---|---|
| Heatmap | `heatmap_constancia.dart:18-20` — `if (minutos <= 0) return 0;` depois `< 30 → 1` | Quadradinho **acende** |
| Quest "Estudar hoje" | `quests_service.dart:68` — `atual: registrosHoje.isEmpty ? 0 : 1` | Quest **conclui**, dá XP |
| Chama do streak | `_diasComEstudoReal` | Streak **quebra** |

O usuário vê o quadrado aceso, a quest verde, e a chama zerada — no mesmo scroll. É a inconsistência, não o valor 15.

**Não é problema:** `DiagnosticoService.pisoMinutosDia = 15` ser uma constante separada. O comentário em `stats_service.dart:195-198` documenta a escolha (serviços de domínio puros, sem dependência cruzada). Unificar num arquivo compartilhado criaria acoplamento que o autor rejeitou de propósito. **Não mexer.**

### Mudança mínima

1. `heatmap_constancia.dart`: `nivelPara` ganha nível 0 para `0 < minutos < 15`, ou um nível visual "abaixo do piso" distinto do dia vazio. **Decisão sua** (ver "Impedimento").
2. `quests_service.dart`: quest de estudo passa a exigir o piso. `QuestsService` é puro e não importa `StatsService`? — **precisa checar antes**: se já importa, usar `StatsService.pisoMinutosStreak`; se não, receber o piso como parâmetro com default, preservando a pureza.

### Arquivos · linhas · motivo

| Arquivo | ~Linhas | Motivo |
|---|---|---|
| `domain/quests_service.dart` | ~8 | Quest de estudo passa a usar a mesma régua do streak |
| `features/dashboard/widgets/heatmap_constancia.dart` | ~5 | Dia abaixo do piso deixa de parecer dia cumprido |
| `test/streak_piso_minutos_test.dart` | ~30 | Estender o arquivo que já existe para M-08 |

### Riscos

- **Regressão de golden**: `01_dashboard` e o heatmap. Mudança de cor de quadrado é diff de pixel legítimo → regravar.
- **XP retroativo**: se a quest passa a exigir 15 min, quests de dias passados que contavam deixam de contar. Gamificação é derivada (nada persistido), então o XP total pode **cair** — o `gamificacao_service.dart:77-80` promete monotonicidade explicitamente. **Risco alto.** Mitigação: aplicar o piso só na quest do dia corrente, nunca retroativo. Confirmar lendo `gamificacao_service` antes.
- Teste `quests_service_test.dart` (se existir) quebra.

### Pronto quando

- Dia com 1-14 min: heatmap não pinta como cumprido, quest não conclui, streak não conta — **as três de acordo**.
- Dia com ≥15 min: as três contam.
- `flutter analyze` limpo · suíte verde · goldens regravados com diff só no heatmap.

### Commits

1. `test:` contraprova — dia de 5 min conta na quest e no heatmap mas não no streak (vermelho)
2. `fix(quests):` piso na quest do dia
3. `fix(heatmap):` nível abaixo do piso
4. `test(goldens):` regravar

---

## ITEM 2 — Cascata de exclusão de aula (D-04)

### Diagnóstico

`AulaUseCase.excluirEmCascata` está correto e completo: cancela lembrete, remove revisões pendentes da aula, limpa `aulaId` dos registros com `semAula(agora)`, remove a aula.

**O furo está no caminho da matéria.** `materia_use_case.dart:29-31`:

```dart
await _ref
    .read(aulasProvider.notifier)
    .removerOnde((a) => a.materiaId == materiaId);
```

Remove as aulas **sem** rodar a cascata delas. Consequência: excluir uma matéria apaga as aulas mas deixa `RegistroHora.aulaId` apontando para aulas inexistentes — exatamente o defeito que D-04 fechou, reintroduzido pela porta de trás.

Registros sobrevivem por decisão explícita (log histórico), então o `aulaId` pendurado **persiste para sempre**.

Confirmação de que ninguém cobre isso: `grep -c aulaId test/materia_cascata_test.dart` → **0**.

Revisões pendentes da aula: já são removidas, porque `Revisao.materiaId` existe (`revisao.dart:7`) e a matéria as varre por `materiaId`. Esse lado está OK.

### Mudança mínima

Em `MateriaUseCase.excluirEmCascata`, antes de remover as aulas, limpar o vínculo dos registros:

```dart
final aulasDaMateria = _ref.read(aulasProvider)
    .where((a) => a.materiaId == materiaId).map((a) => a.id).toSet();
// limpar aulaId dos registros cujo aulaId ∈ aulasDaMateria, via semAula(agora)
```

Reusar `RegistroHora.semAula` (já existe, `registro_hora.dart:148`). **Não** chamar `AulaUseCase.excluirEmCascata` em laço: ela relê providers a cada iteração e removeria revisões uma a uma, com N escritas — pior e mais lento.

### Arquivos · linhas · motivo

| Arquivo | ~Linhas | Motivo |
|---|---|---|
| `application/materia_use_case.dart` | ~10 | Excluir matéria deixava `aulaId` órfão nos registros |
| `test/materia_cascata_test.dart` | ~35 | Cobrir o furo (hoje: 0 menções a `aulaId`) |

### Riscos

- Registros ganham `atualizadoEm` novo → afeta a sincronização futura (`d8d056d`). É o mesmo efeito que `AulaUseCase` já produz; consistente.
- Baixo risco geral: `semAula` já é testado no caminho da aula.

### Pronto quando

- Teste: matéria com aula + registro vinculado → excluir matéria → registro sobrevive **com `aulaId == null`**.
- Nenhum `RegistroHora` no banco com `aulaId` que não resolve, por nenhum caminho de exclusão.

### Commits

1. `test:` contraprova em `materia_cascata_test.dart` (vermelho)
2. `fix(D-04):` cascata de aula no caminho da matéria

---

## ITEM 3 — Card unificado "Plano de hoje"

### Diagnóstico

Quatro superfícies disputam a pergunta "o que eu faço hoje?", todas na mesma tela (`dashboard_screen.dart:135-152`):

| Widget | LOC | O que mostra |
|---|---|---|
| `hero_missao_hoje.dart` | 115 | "O próximo passo de estudo como elemento primário" |
| `card_melhorar_hoje.dart` | 82 | Recomendações do `InsightsService` |
| `card_quests.dart` | 129 | Quests do dia com progresso |
| `card_plano.dart` | 106 | Planejado vs feito vs restante (semana/mês/ano) |

`card_plano` é o único que **não** é sobre hoje — é agregado de período. Nome colide, conteúdo não.

### Impedimento — precisa de decisão sua antes de eu executar

Não consigo escolher sozinho **quais** dos quatro morrem. É decisão de produto, não técnica, e a errada apaga trabalho seu. Preciso de uma das opções:

| Opção | Unifica | Preserva |
|---|---|---|
| A | `hero_missao_hoje` + `card_quests` num "Plano de hoje" | `card_melhorar_hoje`, `card_plano` |
| B | `hero_missao_hoje` + `card_quests` + `card_melhorar_hoje` | `card_plano` (renomeado p/ "Planejado vs feito") |
| C | Só renomear/reordenar, sem fundir | tudo |

**Recomendo B**: as três respondem "hoje" e competem; `card_plano` responde outra pergunta e só precisa de nome que não colida.

### Riscos

- Maior risco visual da onda: mexe no herói do dashboard, a área mais retrabalhada do repo (14 alterações em `dashboard_screen.dart`).
- Goldens `01_dashboard` e `02_dashboard_vazio` mudam por definição.
- `test/acessibilidade_test.dart` testa Semantics dos KPIs e do herói — quebra se a árvore mudar.
- Masonry (`flutter_staggered_grid_view`) pode reflowar as outras colunas.

### Pronto quando

- Uma única superfície responde "o que faço hoje", sem repetir a mesma informação em dois cards.
- Nenhuma informação que existia hoje some sem decisão registrada.
- Goldens regravados · a11y verde.

### Commits

1. `feat(dashboard):` novo card unificado, atrás do mesmo conjunto de providers
2. `refactor(dashboard):` remover os cards absorvidos
3. `test:` a11y do card novo
4. `test(goldens):` regravar

---

## ITEM 4 — Revisões do dia concluíveis no dashboard

### Diagnóstico

A API de conclusão existe e é rica (`revisao_use_case.dart:34-39`):

```dart
Future<ResultadoConclusao> concluir(
  Revisao revisao, { int? questoes, int? acertos, int? minutos });
```

O dashboard hoje só **navega**: `card_forecast_revisao.dart:24` e `hero_geral.dart:92` fazem `ir(Abas.revisoes)`. Concluir exige sair do dashboard.

### Mudança mínima

Card com as revisões vencidas/de hoje e ação de concluir, chamando `revisaoUseCaseProvider`. **Sem** duplicar a lógica de FSRS — só chamar.

Ponto de atenção: `concluir` aceita `questoes`/`acertos`; a tela de Revisões pergunta isso num diálogo (`revisoes_screen.dart:139-140` tem os controllers). No dashboard, decidir entre (a) concluir direto com `minutosPadraoRevisao` e sem questões, ou (b) abrir o mesmo diálogo. **(b)** reusa e não cria segundo caminho de dado — mas exige extrair o diálogo, o que toca `revisoes_screen.dart`.

### Arquivos · linhas · motivo

| Arquivo | ~Linhas | Motivo |
|---|---|---|
| `features/dashboard/dashboard_providers.dart` | ~15 | Provider de revisões vencidas/hoje no ambiente ativo |
| `widgets/card_revisoes_hoje.dart` (novo) | ~120 | Concluir sem sair do dashboard |
| `features/revisoes/revisoes_screen.dart` | ~20 | Extrair o diálogo de conclusão para reuso |
| `dashboard_screen.dart` | ~3 | Encaixar o card |
| `test/` | ~60 | Concluir pelo dashboard = mesmo efeito que pela tela |

### Riscos

- **Escrita real no Hive disparada por tap dentro de `testWidgets`** exige `tester.runAsync` — armadilha documentada em `caderno_screen_test.dart:18-25` e `sidebar_test.dart`. Vai morder.
- Se o item 3 fundir cards, este card entra num dashboard que acabou de mudar → **item 4 depende do item 3**. A ordem que você fixou já respeita isso.
- Conclusão dispara FSRS + XP + notificação cancelada: efeito colateral amplo para um tap no dashboard. Precisa de confirmação ou desfazer.

### Pronto quando

- Concluir pelo dashboard produz **exatamente** o mesmo estado que concluir pela tela de Revisões (teste comparando os dois caminhos).
- Lista some do card ao concluir, sem recarregar a tela.

### Commits

1. `refactor(revisoes):` extrair diálogo de conclusão
2. `feat(dashboard):` provider de revisões de hoje
3. `feat(dashboard):` card com ação de concluir
4. `test:` paridade entre os dois caminhos

---

## ITEM 5 — Localização pt-BR

### Diagnóstico

**Date pickers: já feito.** `app.dart:60-66`:

```dart
locale: const Locale('pt', 'BR'),
supportedLocales: const [Locale('pt', 'BR')],
localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```

Os 8 `showDatePicker`/`showTimePicker` herdam disso. `initializeDateFormatting` não é necessário: todo `DateFormat` do projeto usa padrão numérico (`'dd/MM/yyyy'`, `'dd/MM'`) — zero mês textual.

**Separador decimal: 1 furo.** `grep -rn "toStringAsFixed([12])" lib/features lib/domain | grep -v replaceAll | grep -v export_service` devolve:

```
lib/features/exportar/exportar_screen.dart:99:  r.paginasPorHora?.toStringAsFixed(1) ?? '',
```

Todo o resto é `toStringAsFixed(0)` (percentual, sem casa decimal — nada a separar) ou já passa por `formatarDecimal` (16 chamadas) ou é CSV para BI, onde o ponto é deliberado (formato de máquina).

**Débito menor:** a lógica `.replaceAll('.', ',')` está copiada em `configuracoes_screen.dart:52` e `export_service.dart:53`, em vez de chamar `formatarDecimal`.

### Mudança mínima

1. `exportar_screen.dart:99` → `formatarDecimal(r.paginasPorHora!, 1)` (confirmar a assinatura antes).
2. Trocar as 2 cópias de `.replaceAll` por `formatarDecimal`.

### Arquivos · linhas · motivo

| Arquivo | ~Linhas | Motivo |
|---|---|---|
| `features/exportar/exportar_screen.dart` | 1 | Único decimal da UI ainda com ponto |
| `features/configuracoes/configuracoes_screen.dart` | ~2 | Cópia da regra que já é função |
| `domain/export_service.dart` | ~2 | idem — **só a linha 53** (o resto é CSV de máquina) |
| `test/` | ~15 | Travar o formato pt-BR |

### Riscos

- **`export_service.dart:88,92,95,134,139` NÃO podem virar vírgula** — são o CSV do modelo estrela para Power BI. Trocar quebra a importação. Só a linha 53 (CSV "Excel pt-BR") usa vírgula.
- Golden `19_configuracoes` pode mudar se a formatação mudar de fato.

### Pronto quando

- Nenhum decimal com ponto em superfície de usuário.
- CSV de BI intacto (teste de export segue verde).

### Commits

1. `fix(i18n):` decimal com vírgula na tela de exportação
2. `refactor:` cópias de `.replaceAll` passam a usar `formatarDecimal`

---

## Resumo da onda

| # | Item | Esforço real | Arquivos | Bloqueio |
|---|---|---|---|---|
| 1 | Piso 15 min | **M** | 3 + testes | Confirmar monotonicidade do XP antes |
| 2 | Cascata de aula | **P** | 2 | nenhum |
| 3 | Card "Plano de hoje" | **G** | 5+ | **decisão de produto: opção A, B ou C** |
| 4 | Revisões no dashboard | **M** | 5 | depende do item 3 |
| 5 | pt-BR | **P** | 3 | nenhum |

**Ordem de risco crescente**, o que coincide com a ordem que você fixou — exceto que o 3 é o maior e mais destrutivo da onda e vem antes do 4, que depende dele. Correto assim.

### Validação obrigatória ao final de cada item

```
flutter analyze
flutter test --exclude-tags screenshots
```

Itens 1, 3 e 4 mexem em pixel → acrescentar `flutter test --tags screenshots` e regravar quando o diff for legítimo.

---

**PARADA — fim do planejamento.** Aguardando: (a) autorização para executar, (b) escolha A/B/C do item 3.
