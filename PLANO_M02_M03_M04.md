# NÓ 6 — Plano: integridade do motor de revisão e XP

Base: `ef14dd2` + working tree da onda P1 (validada, não commitada).
**Planejado, não executado.**

---

## FASE 0 — Contexto

| Arquivo | LOC | Papel |
|---|---|---|
| `lib/domain/revisao_service.dart` | 246 | FSRS-lite puro: `proximoPassoFsrs`, `taxaAcertoDe`, `forecastCarga`, `reagendarPorEstudo` |
| `lib/application/revisao_use_case.dart` | 165 | Orquestra conclusão: sessão prática → taxa → passo FSRS → próxima revisão |
| `lib/domain/gamificacao_service.dart` | 191 | XP, níveis, badges. `bonusRevisoes`, `xpPonderado`, `xpDetalhado` |
| `lib/domain/caderno_erros_service.dart` | — | **Segundo consumidor de `proximoPassoFsrs`** (linha 67) |

### Testes de FSRS / revisão / XP

| Arquivo | Cobre |
|---|---|
| `test/uat/uat_fsrs_test.dart` | UAT-B1..B10 — passo FSRS puro, incluindo **B4 antecipação** e B9 estado corrompido |
| `test/uat/uat_revisoes_em_dia_test.dart` | UAT-H1..H8 — conclusão ponta a ponta via harness `Mundo` |
| `test/correcoes_auditoria_test.dart` | Grupos **M-03** (linha 11) e **M-02** (linha 98) |
| `test/revisao_service_test.dart` · `revisao_desempenho_test.dart` · `gamificacao_service_test.dart` · `revisao_test.dart` | unidade |

---

## Veredito: 2 dos 3 já estão fechados

Antes do plano, o diagnóstico. Não vou fabricar trabalho onde não há.

### M-03 — conclusão antecipada · **FECHADO, sem furo**

Implementado em `revisao_service.dart:192-206` e aplicado na linha 224:

```dart
final decorrido = max(1, base + diasDeAtraso);   // diasDeAtraso < 0 = antecipada
final fracaoDecorrida = base <= 0 ? 1.0 : (decorrido / base).clamp(0.0, 1.0);
...
crescimento *= fracaoDecorrida;                  // freio de antecipação
```

O comentário da linha 193-196 descreve o defeito original: *"antes era clampado em 0, e revisar hoje uma revisão de 60 dias consolidava como se os 60 dias tivessem passado — dava para queimar a cadeia inteira num dia"*.

**Cobertura:** `correcoes_auditoria_test:11` (antecipada < 5% de ganho vs em dia > 30%) e `UAT-B4`.

**Verificação de furo residual — os dois consumidores de produção passam `diasDeAtraso` calculado:**

| Call site | Linha | Passa `diasDeAtraso`? |
|---|---|---|
| `revisao_use_case.dart` | 88-95 | sim — diferença entre DIAS de calendário |
| `caderno_erros_service.dart` | 67-74 | sim — `hoje.difference(questao.proximaTentativa).inDays` |

**Nada a fazer.**

### M-04 — nota da própria revisão como sinal primário · **FECHADO, sem furo**

`revisao_use_case.dart:73-81`:

```dart
final taxaDaRevisao = (questoes != null && questoes > 0 && acertos != null)
    ? (acertos.clamp(0, questoes)) / questoes : null;
final taxaJanela = RevisaoService.taxaAcertoDe(...);
final taxa = taxaDaRevisao ?? taxaJanela;   // própria revisão PRIMEIRO
```

Comentário na linha 67 documenta o porquê: a janela de 10 sessões diluía um 0/10 do recall entre sessões boas de outros tópicos, e pior nas cadeias de aula (sem `topicoId`, julgadas pela matéria inteira).

**Cobertura:** UAT-H1 (sem questões → usa janela) e UAT-H2 (com questões → `taxa == 0.95`, ignora janela).

**Nada a fazer.**

### M-02 — XP infinito · **PARCIALMENTE fechado. Furo real.**

Detalhe no item abaixo.

---

## ITEM 3 (único com trabalho) — M-02

### Diagnóstico

O teto existe e funciona, mas cobre **só metade do XP**.

`gamificacao_service.dart:29-52` — `maxRevisoesComBonusPorDia = 3`, aplicado em `bonusRevisoes`. Comentário: *"Sem ele o loop 'criar revisão manual → concluir em 1 clique → +50 XP' era infinito"*.

Só que `xpDetalhado` tem **três** parcelas:

```dart
total = xpPonderado(registros)      // ← minutos. SEM TETO.
      + bonusRevisoes(revisoes)     // ← com teto (M-02)
      + streakPicoComCongelamento × 10
```

E `revisao_use_case.dart:46-62` grava uma sessão a cada conclusão com questões:

```dart
final minutosDaSessao = minutos ?? config.minutosPadraoRevisao;  // padrão 10, máx 60
if (questoes != null && questoes > 0 && acertos != null) {
  await ...salvar(RegistroHora(..., minutos: minutosDaSessao, ...));
}
```

**O loop que sobrou:**

| Passo | Efeito |
|---|---|
| Concluir revisão informando "1 questão, 1 acerto" | +10 min no `xpPonderado` · +50 XP de bônus (até 3/dia) |
| A conclusão agenda a próxima automaticamente | nova revisão pendente aparece na tela |
| Concluir a próxima **antecipada** (a tela lista todas as pendentes, não só as vencidas) | repete |

Em um dia: o bônus trava em 150 XP, mas a base cresce **10 XP por conclusão, sem limite**. Com `minutosPadraoRevisao = 60` (valor máximo aceito), são 60 XP por clique.

**Efeito colateral pior que o XP:** 2 conclusões = 20 min ≥ `pisoMinutosStreak` (15). Isso sustenta o streak e acende o heatmap sem nenhum estudo — reabre pela porta lateral exatamente o M-08 que acabamos de fechar.

M-03 amortece a *cadeia FSRS* na antecipação, mas não toca no XP nem nos minutos: o freio é sobre `crescimento`, não sobre a gravação da sessão.

### IMPEDIMENTO — a UAT derivou da produção e não enxerga este furo

`test/uat/uat_revisoes_em_dia_test.dart:14-24` define o harness `Mundo`, que é uma **reimplementação à mão** de `RevisaoUseCase.concluir` (necessária: o use case pede `Ref` do Riverpod). A assinatura:

```dart
int minutos = 0, // <- default do use case; revisoes_screen NAO passa minutos
```

**Esse comentário é falso hoje.** Produção faz `minutos ?? config.minutosPadraoRevisao`, cujo padrão é 10 (`configuracoes.dart:41`). O espelho ficou em 0.

Consequência direta — UAT-H2 afirma o contrário do que produção faz:

```dart
expect(nova.minutos, 0, reason: 'revisoes_screen nao pergunta minutos');
expect(StatsService.minutosNoDia(m.registros, agora), antesMin, reason: 'horas nao se movem');
```

Em produção as horas **se movem** (10 min por conclusão) desde a entrega B1. A suíte UAT está verde medindo um modelo que não existe mais.

**Isso bloqueia o M-02:** consertar o teto sem antes reconciliar o espelho significa validar a correção contra um harness cego para o defeito. Corrigir o espelho é pré-requisito, não escopo extra.

### Decisão de produto necessária antes de eu executar

Como fechar o furo da base de XP. As quatro são implementáveis; a escolha muda o que o usuário vê.

| Opção | O que faz | Custo | Efeito colateral |
|---|---|---|---|
| **A** | Não creditar minutos quando `diasDeAtraso < 0` (conclusão antecipada) | ~6 linhas em `revisao_use_case` | Quem revisa adiantado de verdade perde o crédito de tempo |
| **B** *(recomendo)* | Teto diário de minutos creditados por revisão, espelhando o teto de bônus: `3 × minutosPadraoRevisao` | ~15 linhas; precisa contar conclusões do dia antes de gravar | Dado gravado passa a depender da ordem do dia — quebra "tudo derivado" |
| **C** | Marcar a sessão como gerada por revisão e excluí-la do `xpPonderado` | Campo novo em `RegistroHora` + `toJson`/`fromJson` + migração | Mexe em schema; o tempo some das horas totais também |
| **D** | Não mexer; documentar como risco aceito | 0 | O loop continua aberto |

**Recomendo B**, com uma ressalva honesta: ela é a única que mantém o teto *coerente* com o `maxRevisoesComBonusPorDia` que já existe — a mesma régua para as duas parcelas de XP. A objeção legítima é que hoje o app grava o que aconteceu e deriva tudo o mais; um teto no momento da gravação introduz decisão no dado. Se essa objeção pesar mais que a coerência, **A** é a segunda melhor: mais simples, sem estado, e ataca o vetor real (o loop depende de concluir antecipadamente).

**C** é a mais correta conceitualmente e a única que também protege streak/heatmap, mas mexe em schema — e schema estava fora do escopo desta onda.

### Mudança mínima (assumindo B)

| Arquivo | ~Linhas | Motivo |
|---|---|---|
| `test/uat/uat_revisoes_em_dia_test.dart` | ~10 | Espelho `Mundo` deixa de mentir sobre `minutos`; UAT-H2 passa a afirmar o que produção faz |
| `lib/domain/gamificacao_service.dart` | ~4 | Expor o teto de minutos ao lado do de bônus — uma constante, uma régua |
| `lib/application/revisao_use_case.dart` | ~15 | Conclusão além do teto diário grava a sessão com 0 min (questões continuam contando) |
| `test/correcoes_auditoria_test.dart` | ~40 | Estender o grupo M-02: base de XP também tem teto |

**Questões nunca são descartadas** em nenhuma opção: elas são dado real de desempenho e alimentam Elo, FSRS e taxa. O que é limitado é só o *tempo* não cronometrado.

### Riscos e regressões

| Risco | Onde bate | Mitigação |
|---|---|---|
| **UAT-H2 muda de expectativa** | `uat_revisoes_em_dia_test.dart:112-131` | É correção de teste desatualizado, não regressão. O diff precisa ficar explícito no commit |
| **UAT-H4** ("fila inteira em dia: efeito no dashboard") mede minutos agregados | linha 147 | Provavelmente muda de número. Recalcular a partir do comportamento real |
| **UAT-H5** (teto de bônus) | linha 172 | Não deve mudar: mexo na base, não no bônus |
| **UAT-H1/H3/H6/H7/H8** | — | Não tocam minutos; devem passar intactos |
| **UAT-B1..B10** | `uat_fsrs_test.dart` | Nenhum toca XP nem minutos — imunes |
| **Monotonicidade do XP** | `xpDetalhado` | Teto no momento da gravação **não** rebaixa XP já ganho: sessões antigas continuam como estão. Cai só o ganho FUTURO. Precisa de teste explícito |
| **Goldens** | `01_dashboard` | Só muda se a fixture concluir revisão — não conclui. Esperado: sem diff |

### Critério de pronto

- Concluir 20 revisões no mesmo dia credita no máximo `3 × minutosPadraoRevisao` minutos e `3 × 50` XP de bônus.
- As 20 conclusões continuam registrando **todas** as questões/acertos.
- `Mundo.concluir` produz o mesmo `minutos` que `RevisaoUseCase.concluir` para a mesma entrada — com teste que compara os dois, para o espelho não derivar de novo.
- XP total nunca cai após a mudança para um histórico já existente.

### Ordem interna de commits

1. `test(uat):` reconciliar o espelho `Mundo` com o use case (UAT-H2/H4 passam a afirmar o comportamento real) — **isolado, sem código de produção**
2. `test:` contraprova do furo — 20 conclusões inflam o XP base (vermelho)
3. `fix(M-02):` teto diário de minutos creditados
4. `test:` monotonicidade — histórico antigo não perde XP

O commit 1 sozinho já tem valor: sem ele, nenhuma medida futura sobre conclusão de revisão é confiável.

---

## Resumo

| # | Item | Estado | Trabalho |
|---|---|---|---|
| 1 | M-03 antecipação | **fechado**, 2 call sites conferidos | nenhum |
| 2 | M-04 nota primária | **fechado**, UAT-H1/H2 cobrem | nenhum |
| 3 | M-02 XP infinito | **furo real** na parcela `xpPonderado` | ~70 linhas, 4 arquivos |
| — | *Achado extra:* espelho UAT derivou da produção | **bloqueia validar o item 3** | ~10 linhas, pré-requisito |

**PARADA — fim do planejamento.** Aguardando: (a) autorização, (b) escolha A/B/C/D para o M-02.
