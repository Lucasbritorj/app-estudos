# NÓ 8 — Plano: Semantics nos 4 cards interativos do Dashboard

Base: `d79b89c` + working tree. **Planejado, não executado.**

---

## FASE 0 — Contexto

Acesso confirmado. Nenhum dos 4 arquivos importa `rotulos_a11y.dart` — hoje só `hero_geral.dart` e `tiles_resumo.dart` importam.

### Padrão da casa (a reusar, não reinventar)

| Referência | Forma |
|---|---|
| `dashboard_screen.dart:69-73` (FAB) | `Semantics(label:, button: true, excludeSemantics: true, onTap:)` |
| `card_diagnostico.dart:43-46` | `Semantics(container: true, excludeSemantics: true, label:)` **restrito à linha do título** |
| `graficos.dart` (3×) | `excludeSemantics: true` + resumo textual sintetizado — gráfico não tem texto para vazar |

**Lição B18, gravada em `card_diagnostico.dart:40-42`:** aplicar `excludeSemantics` ao card inteiro apaga mensagem e evidências da árvore. Restringir ao trecho que o rótulo já descreve.

### Helpers disponíveis em `rotulos_a11y.dart`

`minutosPorExtenso(int)` · `ritmoPorExtenso(double)` · `variacaoPorExtenso(double, String)`

**Aplicabilidade real:** só `card_plano_de_hoje` tem abreviação de tempo (`formatarMinutos` → "2h 15min", que o leitor lê como "dois h"). Os outros 3 expõem contagens e nomes — nenhum helper existente se aplica, e criar novo estaria fora do escopo mínimo.

### Inventário por arquivo

| # | Arquivo | Interativos | O que o leitor ouve hoje |
|---|---|---|---|
| 1 | `card_plano_de_hoje.dart` | `FilledButton.icon` "Estudar agora" (`:190`) · `TextButton` "Registrar manualmente" (`:197`) · `InkWell` por insight com `materiaId` (`:317`) · seção `_Quests` (não interativa) | Botões: só o texto visível, sem contexto de matéria. Insights: `InkWell` **sem rótulo nenhum** — nó tocável anônimo. Quests: `Icon` + textos soltos |
| 2 | `card_revisoes_hoje.dart` | `IconButton` concluir por linha, até 4 (`:143`) · `TextButton` "Ver todas (+N)" (`:76`) | `IconButton` tem `tooltip: 'Concluir: <título>'` — **é o único rótulo do card**. "Ver todas" e as linhas (matéria · situação) não têm rótulo próprio |
| 3 | `card_forecast_revisao.dart` | `InkWell` no card inteiro (`:23`) → `ir(Abas.revisoes)` | Nada. `InkWell` anônimo + 30 barras `DecoratedBox` sem texto + "hoje"/"pico: N em D+X"/"+30d" fragmentados |
| 4 | `card_simulados.dart` | `InkWell` no card inteiro (`:35`) → `Navigator.push(SimuladosScreen)` | Nada. Ouve "Simulados & Provas", "+3 pp", "ver todos", depois cada linha em pedaços |

---

## FASE 1 — Planejamento por card

### Card 1 — `card_plano_de_hoje.dart`

**Diagnóstico.** Zero `Semantics` no arquivo. Três problemas distintos:

- `:190,197` — `FilledButton.icon(label: Text('Estudar agora'))` é rótulo **visual**. O leitor ouve "Estudar agora, botão" sem saber *o quê*. A matéria e o tópico estão em `Text` irmãos (`:167`, `:180`).
- `:317` — `InkWell(onTap: acao.materiaId == null ? null : ...)`: quando tocável, é um nó sem nome. Quando não tocável, é texto solto.
- `:180` — `'Faltam ${formatarMinutos(sugestao.deficitMinutos)} no ciclo...'` → "Faltam 2h 15min" lido como "faltam dois h quinze min".

**Mudança mínima**

| Alvo | Forma |
|---|---|
| Bloco `_Missao` | `Semantics(container: true, excludeSemantics: true, label: ...)` **só na linha matéria + déficit** (`:161-183`), usando `minutosPorExtenso`. Os botões ficam FORA do exclude — senão perdem a semântica de botão |
| `FilledButton` "Estudar agora" | `Semantics(button: true, label: 'Estudar <matéria> agora no cronômetro')` |
| `TextButton` "Registrar manualmente" | `Semantics(button: true, label: 'Registrar sessão de <matéria> manualmente')` |
| Cada `InkWell` de insight | `Semantics(button: true, label: '<mensagem>. Registrar sessão de <matéria>')` quando `materiaId != null` |

**Rótulos propostos**

| Elemento | Rótulo |
|---|---|
| Bloco missão | `Plano de hoje: <matéria>. Faltam <X horas e Y minutos> no ciclo desta semana[, próximo tópico: <nome>]` |
| Estudar agora | `Estudar <matéria> agora no cronômetro` |
| Registrar manualmente | `Registrar sessão de <matéria> manualmente` |
| Insight acionável | `<mensagem>. Registrar sessão de <matéria>` |

**Risco.** `acessibilidade_test.dart` **não cobre este card** (nasceu na fusão de ontem). Golden `01_dashboard` renderiza-o no topo — `Semantics` não pinta, então **espero zero diff de pixel**. `dashboard_screen_test.dart` asserta `find.text('PLANO DE HOJE')` e `'O que melhorar hoje'`: se eu usar `excludeSemantics` largo demais, o `find.text` continua funcionando (busca a árvore de widgets, não a semântica) — sem risco.

**Pronto quando.** Os 4 tipos de nó tocável têm nome próprio; nenhum rótulo repete; `minutosPorExtenso` usado em vez de `formatarMinutos` no nó semântico; teste novo em `acessibilidade_test.dart`.

---

### Card 2 — `card_revisoes_hoje.dart`

**Diagnóstico.** `:143` tem `tooltip: 'Concluir: ${revisao.titulo}'` — funciona, mas `Tooltip` vira propriedade `tooltip` do nó, **não** o `label` primário; o leitor anuncia "botão" e só depois a dica. Já é a lição registrada em `dashboard_screen.dart:65-68` para o FAB, e aqui não foi aplicada.
`:76` — `TextButton(child: Text('Ver todas (+N)'))` sem rótulo.
`:112-137` — cada linha (título, matéria, situação) fica em 2 `Text` irmãos.

**Mudança mínima**

| Alvo | Forma |
|---|---|
| `_Linha` inteira | `Semantics(container: true, excludeSemantics: true, label: '<título>, <matéria>, <situação>')` no bloco de texto — o `IconButton` fica fora |
| `IconButton` | Trocar `tooltip` por `Semantics(button: true, label: 'Concluir revisão <título>')` **mantendo** o `tooltip` (dica visual no hover é útil e não conflita) |
| `TextButton` "Ver todas" | `Semantics(button: true, label: 'Ver todas as revisões, mais <N>')` |

**Rótulos propostos**

| Elemento | Rótulo |
|---|---|
| Linha | `<título>, <matéria>, atrasada <N dias>` / `..., vence hoje` |
| Concluir | `Concluir revisão <título>` |
| Ver todas | `Ver todas as revisões, mais <N>` |

**Risco.** `revisoes_no_dashboard_test.dart` usa `find.byIcon(Icons.check_circle_outline)` e `find.text('Ver todas (+3)')` — ambos sobrevivem a `Semantics`. **Mas** se eu remover o `tooltip`, nada quebra (nenhum teste usa `byTooltip` aqui) — ainda assim vou **manter** o tooltip. Golden: sem diff esperado.

**Pronto quando.** 3 tipos de nó nomeados; a situação de atraso está no rótulo (não só na cor); teste de a11y cobrindo linha + botão.

---

### Card 3 — `card_forecast_revisao.dart`

**Diagnóstico.** `:23` — `InkWell` envolvendo o card inteiro, anônimo. O interior é um gráfico de 30 `DecoratedBox` **sem texto nenhum** mais 3 rótulos de eixo fragmentados. É exatamente o caso que `graficos.dart` resolve com `excludeSemantics` + resumo sintetizado.

**Mudança mínima.** `Semantics(button: true, container: true, excludeSemantics: true, label: ..., onTap: ...)` envolvendo o `InkWell`. Aqui o exclude é seguro e correto: não há conteúdo textual que valha preservar, e sem ele o leitor varre 30 barras vazias.

**Rótulo proposto** — precisa ser **distinto** do card 2 (regra de desempate):

```
Carga de revisões dos próximos 30 dias: <N> no total, pico de <P> em <hoje|D+X>. Abrir revisões
```

| Card | Palavra-chave que distingue |
|---|---|
| `CardRevisoesHoje` | **"Revisões de hoje"** + "Ver todas" |
| `CardForecastRevisao` | **"Carga de revisões dos próximos 30 dias"** |

**Risco.** Nenhum teste referencia este card por texto. `card_forecast_revisao_test.dart` existe — precisa ser lido antes de editar (não li ainda; é o único ponto que não verifiquei). Golden: sem diff esperado.

**Pronto quando.** Um nó de botão nomeado; as 30 barras não aparecem na árvore semântica; o nome não colide com o card 2.

---

### Card 4 — `card_simulados.dart`

**Diagnóstico.** `:35` — `InkWell` no card inteiro, anônimo. Diferente do card 3, **o interior tem informação real**: até 3 linhas com nome, data, acertos/total, taxa e min/q (`:96-134`).

**Mudança mínima.** `Semantics(button: true, label: ..., onTap: ...)` **sem `excludeSemantics`** — o rótulo dá o nome e a variação; as linhas seguem exploráveis. É a diferença deliberada em relação ao card 3, e é a lição do B18 aplicada.

**Rótulo proposto**

```
Simulados e provas: <N> registrados[, variação de <±X> pontos percentuais no último]. Abrir lista
```

**Impedimento menor a registrar.** `:126` — `'${formatarDecimal(s.minutosPorQuestao!)} min/q'` sofre do mesmo problema de abreviação que `minutosPorExtenso` resolve para horas, mas **não existe helper para "min/q"** e criar um está fora do escopo fechado. Fica como débito nomeado, não corrigido nesta rodada.

**Risco.** Sem `excludeSemantics`, a árvore semântica ganha um nó de botão **acima** dos nós de texto existentes — nenhum nó some. Golden: sem diff esperado.

**Pronto quando.** Botão nomeado com contagem; as linhas continuam legíveis individualmente pelo leitor.

---

## Riscos transversais

| Risco | Avaliação |
|---|---|
| **Golden `01_dashboard`** | `Semantics` é nó de acessibilidade, não pinta. **Previsão: zero diff.** Se der diff, paro e reporto — seria sinal de que mexi em layout sem querer |
| **Golden `02_dashboard_vazio`** | Os 4 cards se auto-escondem no estado vazio → intocado |
| `acessibilidade_test.dart` | Só **adiciona** casos; os 11 existentes não tocam estes 4 cards |
| `dashboard_screen_test.dart` | Usa `find.text` / `find.byType` — insensível a `Semantics` |
| `revisoes_no_dashboard_test.dart` | Usa `find.byIcon` e `find.text` — insensível |
| **Vazamento semântico** (B18) | O erro provável: `excludeSemantics` largo apagando conteúdo útil. Mitigado por card: **exclude só no card 3** (gráfico sem texto) e no bloco de missão do card 1 |
| `card_forecast_revisao_test.dart` | **Não li ainda.** Único arquivo do escopo cuja cobertura atual desconheço — leio antes de tocar no card 3 |

## Ordem de execução e commits

| Ordem | Card | Commits |
|---|---|---|
| 1 | `card_plano_de_hoje` | `feat(a11y): rótulos do Plano de hoje` + `test(a11y)` |
| 2 | `card_revisoes_hoje` | `feat(a11y): rótulos das revisões de hoje` + `test(a11y)` |
| 3 | `card_forecast_revisao` | `feat(a11y): resumo falado do forecast` + `test(a11y)` |
| 4 | `card_simulados` | `feat(a11y): rótulo do card de simulados` + `test(a11y)` |

Validação após cada card:

```
flutter analyze
flutter test --exclude-tags screenshots
```

Ao final dos 4, uma passada única de goldens (`flutter test --tags screenshots`) — esperado 19/19 sem diff.

---

**PARADA — fim do planejamento.** Aguardando autorização.
