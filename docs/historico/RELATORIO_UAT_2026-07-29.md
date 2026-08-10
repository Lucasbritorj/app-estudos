# Relatório de UAT — app_estudos (ciclo agêntico) — 2026-07-29

> **Onda 2 (30/07): Flutter SDK real + 4 features novas.** O §5 no fim deste
> documento cobre a segunda rodada: `flutter test` de verdade (621 testes),
> Caderno de Erros, Desempenho por banca, Edital verticalizado e Prova
> cronometrada, mais 2 defeitos visuais que só apareceram com a tela renderizada.
> As seções 1-4 abaixo são da onda 1 (auditoria + correções), preservadas como
> registro.

**Escopo executado de verdade:** Dart SDK **3.12.2** (idêntico ao `environment.sdk: ^3.12.2` do
`pubspec.yaml`) provisionado no sandbox; harness de UAT importando o **código de produção real**
de `lib/domain/**` e `lib/data/models/**` (camada 100% pura — únicas dependências externas:
`archive 4.0.9` e `xml 7.0.1`, mesmas versões do `pubspec.lock`).

**Resultado:** **89 testes de UAT, todos verdes** (inclusive as regressões dos **9 defeitos
corrigidos**). Suíte portada para o repo em `test/uat/` (11 arquivos). Diff de produção:
**14 arquivos, +211/−28**.

> **Limite honesto de cobertura.** Não havia Flutter SDK no ambiente de execução, então
> **camada de aplicação (Riverpod), persistência (Hive) e widgets (Lumina) NÃO foram executados**.
> Para essas camadas: auditoria estática linha a linha + **transcrição fiel** da lógica pura para
> dentro do harness (indicada arquivo:linha em cada caso). Onde há transcrição, o texto diz
> explicitamente. Nada abaixo foi inferido de "saída simulada".
> Pendência de validação local: `flutter test` (suíte antiga, 60 arquivos) + `flutter test test/uat`.

---

# 1. PLANO ESTRATÉGICO DE UAT (matriz de riscos e cobertura)

## 1.1 Mapa de risco por camada

| Camada | Arquivos-chave | Risco dominante | Executável no sandbox |
|---|---|---|---|
| Domínio puro | 20 serviços, 9 modelos | erro de cálculo silencioso, NaN, divisão por zero | **Sim** |
| Aplicação | 6 use cases (`materia`, `aula`, `revisao`, `sessao`, `apagar_dados`) | cascata incompleta → órfãos no doc-store sem FK | Não (Riverpod) |
| Persistência | `_HiveRepositorio<T>`, 10 boxes | ausência de transação entre boxes; tombstones | Não (Hive) |
| UI/Lumina | 40+ widgets | contraste WCAG, estado degenerado sem crash | Não (só análise) |

## 1.2 Matriz de cenários (ID → risco coberto)

| ID | Cenário | Risco de regressão em cascata |
|---|---|---|
| **A1-A9** | Carga da massa fake e ciclo diário | agregados divergentes entre cards do dashboard |
| **B1-B10** | FSRS-lite: cadeia, lapso, antecipação, atraso, teto, estado corrompido | super/sub-espaçamento; `NaN` matando a cadeia |
| **C1-C7** | Rendimento: 0 questões, `acertos > questoes`, ponderação | `0/0` → NaN; % inventado; média de médias |
| **D1-D9** | Streak: piso, congelamento, recuperação, virada de ano/mês | incoerência chama × badge × XP |
| **E1-E7** | **Destrutivo:** excluir matéria com histórico, aula, todas as matérias | órfãos em gráficos, XP, export, prontidão |
| **F1-F9** | Hierarquia de tópicos: filhos, órfãos, ciclo, 500 níveis | tópico invisível; recursão infinita |
| **G1-G11** | Export/import: round-trip, rejeições, CSV injection, ZIP estrela | perda de dado irreversível; import parcial |
| **H1-H8** | Revisões em dia **com** e **sem** informação | dashboard registrando o que não deveria (e vice-versa) |
| **I1-I4** | Insights: régua do alerta de streak e constante citada | mensagem divergir do número da chama |
| **REG-1..10** | Reexecução das expectativas da suíte antiga afetadas pelas correções | correção quebrar contrato já aceito |

## 1.3 Riscos de cascata mapeados antes de executar

1. `Materia` tem tombstone (`excluidaEm`), `Topico` **não** → cascatas assimétricas.
2. `MateriaUseCase` remove tópicos/aulas/revisões pendentes, mas **preserva registros** (promessa de
   UI) → `RegistroHora.materiaId`/`topicoId` ficam pendurados. `AulaUseCase`, ao contrário, limpa o
   vínculo (`semAula`). Assimetria = fonte provável de bug.
3. Exclusão de **tópico** não tem use case: é `repositorio.remover(id)` direto na tela.
4. `Revisao.fromJson` não valida `estabilidade`/`dificuldade` (os outros modelos validam).
5. `substituirTudo` por box, sem transação → import interrompido deixa estado misto.

---

# 2. ROTEIRO DE TESTES DE ACEITAÇÃO (passo a passo com massa fake)

Massa determinística (`test/uat/_massa_fake.dart`, `Random(42)`, âncora `hoje = 2026-07-29`,
zero `DateTime.now()`):

| Entidade | Volume | Detalhe |
|---|---|---|
| Ambiente | 1 | "Concurso TRF 2026", prova em 15/11/2026 (+109d) |
| Matérias | 5 | Português (p3), D. Constitucional (p5), D. Administrativo (p4), RLM (p2), Informática (p1, **sem questões de propósito**) |
| Tópicos | 9 | 2 níveis (`Direitos Fundamentais` → `Art. 5º`, `Remédios`) + 1 aresta de DAG (`Remédios` requer `Art. 5º`) |
| Aulas | 3 | 2 concluídas (disparam cadeia), 1 em 25/60 páginas |
| Registros | 71 em 50 dias | 60 dias corridos, domingo de descanso, furos deliberados em `-12` e `-3` |
| Revisões | 11 | 2 atrasadas, 2 vencendo hoje, 3 futuras, 4 feitas (com carimbo) |
| Plano | seg–sáb 90 min | domingo 0 |

**Roteiro (o que o operador faz na mão / o que o teste automatiza):**

1. **Carga** — semear e conferir volumetria e horas líquidas (`A1`, `A2`).
2. **Ciclo diário** — abrir dashboard: hoje/semana/mês/ano, série de 30 dias, MoM/YoY (`A2`–`A4`).
3. **Rendimento** — conferir % por matéria e geral; confirmar que **Informática não aparece**
   (sem questões ≠ 0%) (`A5`, `C1`, `C7`).
4. **Gamificação** — chama, congelados, XP detalhado, nível, badges (`A6`).
5. **Prontidão** — Elo por matéria, prontidão bruta/ajustada, cobertura confiável (`A7`).
6. **Fila de revisão** — atrasadas/hoje/futuras + forecast de 30 dias (`A8`).
7. **FSRS** — concluir revisão em dia, atrasada, adiantada, com e sem questões (`B*`, `H*`).
8. **Colocar revisões em dia** — botão "Só concluir" (sem info) × "Concluir e registrar"
   (com questões) e medir o delta no dashboard (`H1`, `H2`, `H4`).
9. **Destrutivo** — excluir matéria com histórico; excluir aula; excluir tópico com filhos;
   excluir tudo (`E1`–`E7`, `F2`).
10. **Hierarquia** — criar subtópico, excluir pai, importar backup com ciclo (`F1`–`F9`).
11. **Export/Import** — CSV pt-BR, CSV BI, ZIP estrela, JSON completo, JSON de 1 ambiente,
    e reimportar em modo mesclar × substituir (`G1`–`G11`).

**Como reexecutar:**

```bash
flutter test test/uat                     # suíte de UAT nova (82 casos)
flutter test                              # suíte completa do repo + UAT
flutter test --tags screenshots --update-goldens   # regravar goldens (ver §4, item 15)
```

---

# 3. DIÁRIO DO CICLO AGÊNTICO (Think → Execute → Test → Verify → Fix → Retry)

**T1 THINK.** Leitura das 4 camadas. Domínio puro confirmado (`grep` de `package:`/`flutter/`
em `lib/domain` + `lib/data/models`: só `archive` e `xml`). Decisão: montar runtime real em vez
de descrever teste no papel.

**E1 EXECUTE.** Sem Flutter no ambiente → baixado Dart SDK 3.12.2 (233 MB) + pacote harness com
`lib/app` → symlink para `lib/` do app. Smoke: `RevisaoService.tetoDiasFsrs == 120`, `pisoMinutosStreak == 15`,
`proximoIntervalo([7,15,30,60],7) == 15`. Código de produção carregando e calculando. OK.

**T2 TEST — massa e ciclo diário.**
`71 registros · 4469 min (74,5 h) · 50 dias distintos`.
`hoje=57 ≤ semana=239 ≤ mês=1990 ≤ ano=4469 = total` (invariante de aninhamento OK).
`MoM 1990 vs 2413 → −17,53%` (parcial-vs-parcial). `YoY: anterior=0 → variação=null` (sem
infinito, sem % inventado).
Rendimento: `Port 149/210=70,95% · Const 169/245=68,98% · Adm 286/415=68,92% · RLM 140/204=68,63% · geral 743/1074=69,27%`.
`Informática` ausente do mapa (0 questões → sem chave).
Prontidão `70,98%`, ajustada `69,31%` (penaliza dispersão), cobertura `93,3%`.
Forecast: `4 revisões no dia 0` (2 atrasadas + 2 de hoje), `6` em 30 dias. Bate com a fila.

**T3 TEST — FSRS-lite.** Cadeia limpa de 7d: `13 → 22 → 39 → 66 → 110` (5 passos, encerra acima
de 120). Difícil (75–84%): `10 → 13 → 17 → 22 → 28 → 34` com D subindo `5,45 → 7,11`. Lapso
(<75%) com S=30: `S→12,0 · 12d · reforço · D 5→5,9`. Antecipação de 59d em S=60: `60d` contra
`95d` em dia → freio funciona. Atraso de 200d em S=20: `44d` contra `34d` → bônus de esquecimento
funciona e respeita o teto. Manual (intervalo 0): `6d` a partir da semente de 3d.
**Achado 3:** `estabilidade = 0` (ou negativa) → `UnsupportedError: Infinity or NaN toInt`.

**T4 TEST — rendimento.** `0 questões → null` em todos os caminhos
(`taxaAcertoGeral`, `desempenhoPorMateria`, `taxaDoTopico`, `taxaAcertoDe`, `dominioDe`).
`acertos=99 / questoes=10 → 10`; `questoes=-5 → 0`; `minutos=999999 → 960` (teto de 16 h);
página negativa → `null`. Ponderação correta: `60/110 = 54,5455%` (não `75%` da média de médias).
Janela de recência: 10 sessões velhas 0% + 10 recentes 100% → `taxa = 1.0`.

**T5 TEST — streak.** Piso por **dia somado**: `8+7 min → conta`; `14 min → não`.
Congelamento: 1 por semana-calendário, exige ≥5 dias na semana anterior. Recuperação: run de 4 →
`recuperados=2`. Virada de ano: streak de 4 atravessa 31/12→01/01; `minutosPorAno {2025:120, 2026:120}`;
`inicioDaSemana(01/01/2026) = 29/12/2025`. `comparativoMensal(31/03)` clampa fevereiro (não estoura
para março).
**Achado 1 (o mais grave):** usuário-modelo seg–sáb por 8 semanas → **chama = 39 dias**,
`streakPico` (cru) **= 6**, `badge streak-7` = **falso**, `bonusStreak` = **60 XP**.

**T6 TEST — destrutivo.** Cascata de `Direito Constitucional` (predicados transcritos de
`materia_use_case.dart:22-35`): morrem 4 tópicos, 1 aula, 2 revisões pendentes; sobrevivem
**21 registros com `materiaId` pendurado**, **21 com `topicoId` pendurado** e 4 revisões feitas.
**Achado 5:** XP `5954 → 5418` (**−536**, −9%) porque `xpPonderado` degrada matéria desconhecida
para ×1,0 — contraria a monotonia documentada no próprio serviço.
**Achado 7:** modelo estrela sai com **71 fatos para 4 linhas de `dim_materia`**.
**Achado 6:** excluir **tópico** deixa revisão pendente viva e agendada (matéria e aula cascateiam,
tópico não). Excluir as 5 matérias: `prontidao = null` (não 0% inventado), fronteira vazia, streak
sobrevive, sem exceção em nenhum agregado.

**T7 TEST — hierarquia.** Ordem em profundidade correta; excluir pai promove filhos a raiz sem
duplicata; 500 níveis sem estouro de pilha; `criariaCiclo` protege `prerequisitos`; pré-requisito
apagado não trava a fronteira; peso de backup nunca rebaixa (<1 → 1).
**Achado 4:** ciclo `a.parent=b, b.parent=a` → **2 de 3 tópicos desaparecem da tela** (seguem
gravados no Hive). Idem auto-pai. `Topico.fromJson` aceita `parentId == id`.

**T8 TEST — export/import.** Round-trip de 42 208 bytes sem perda (datas, minutos, tipo, páginas,
`estabilidade`/`dificuldade`, `parentId`, `prerequisitos`). 8 entradas inválidas → 8 `FormatException`
(nenhum import parcial silencioso). Backup antigo cai no ambiente `Geral`; dias 0 e 9 do plano
descartados; plano negativo → 0. CSV injection neutralizada nos **três** exports (`'=HYPERLINK`,
`'@SUM`, `'-2+3`). ZIP: 5 tabelas, 3005 bytes, `dim_data` contínua (59 dias).
**Achado 2:** backup de **um ambiente** carrega `leituras=[]`, `resumos=[]`, `planejamento={}` e o
fluxo "Validar e importar" chamava `substituirTudo([])` nessas coleções → **apagava leituras,
resumos e cronograma inteiros, sem volta**.

**T9 TEST — revisões em dia (item 7 do escopo).**
- **Sem informação** ("Só concluir"): nenhuma sessão criada; `min_hoje` e questões **inalterados**;
  `atrasadas 2→1`; `XP +50`; taxa usada = **janela das últimas 10 sessões do tópico** (`0,7040`)
  → como está abaixo de 75%, o passo virou **reforço**.
- **Com informação** (20 questões, 19 acertos): cria `RegistroHora` **prática de 0 min**;
  `min_hoje` não muda (correto), questões e taxa entram; taxa usada = `0,95` (sinal primário,
  ignora a janela); próxima em `13d`.
- Fila inteira em dia: `atrasadas → 0`, badge "Em dia" acende, XP `+150` para 4 conclusões
  (teto de 3/dia respeitado — anti-farm OK).
- Antecipação de 41 dias com 100% de acerto: `60d → 69d` (não queima a cadeia). Contraprova sem
  informação: cai em lapso `S=24 → 24d` pela janela de 70,95% — **não** pelo freio.

**F1 FIX & RETRY — 9 correções aplicadas e reverificadas por execução:**

| # | Arquivo | Correção | Prova |
|---|---|---|---|
| 1 | `stats_service.dart` + `gamificacao_service.dart` | `streakPicoComCongelamento()` (mesma régua do contador exibido) alimentando badge e bônus | `D5`: chama 39 → `picoCong=39`, `streak-7` e `streak-30` acendem, bônus `60 → 390 XP` |
| 2 | `export_service.dart` + `import_service.dart` + `exportar_screen.dart` | campo `escopo` no backup parcial + `backup.parcial` + bloqueio do "substituir tudo" | `G6`: `parcial=true` no backup de ambiente, `false` no completo e no legado; `escopo:42` não lança |
| 3 | `revisao_service.dart` | sanitização de `S`/`D` não finitos ou ≤ 0 → cai na semente | `B9`/`G5`: `S ∈ {0, −5, NaN, ∞}` e `D=NaN` → `6d`, sem exceção |
| 4 | `topicos_screen.dart` | `emitidos` (emite cada tópico uma vez) + fallback cobre órfão **e** nó em ciclo | `F3`/`F4`/`F4b`: ciclo de 2 e de 3 + auto-pai → 100% dos tópicos visíveis, sem duplicata |
| 5 | `repositorios.dart` + `dashboard_providers.dart` | `MateriasRepositorio.pesosHistoricos()` lê o box (inclui tombstone) e alimenta o XP ponderado | `E2`: excluir matéria peso 5 → só-vivas `−536 XP` (nível 4) × históricos `delta 0` (nível 5) |
| 6 | **novo** `application/topico_use_case.dart` + `topico.dart` + `topicos_screen.dart` | cascata de tópico: remove revisão pendente, reparenta filhos para o avô, limpa pré-requisito pendurado; `Topico.copyWith(limparParent:)` | `E5`: pendentes `1 → 0`, feitas e registros intactos, `prerequisitos` limpo. `E5b`: neto sobe para `top-df`; excluir raiz → filho vira raiz |
| 7 | `export_service.modeloEstrela` | linha sintética de dimensão para chave que só existe no fato | `E4`: `fato(materia_id) ⊄ dim_materia` → conjunto-diferença **vazio**; `G8b`: sem órfão, nenhuma linha extra |
| 8 | `app_theme.dart` + `configuracoes_screen.dart` | `critico` vira tinta `#E06A63` (4,91:1) e nasce `criticoSuperficie #D03B3B` para fundo destrutivo com rótulo branco (4,80:1) | contraste recalculado (§4.2 #8) |
| 9 | `revisao_use_case.dart` | `diasDeAtraso` por diferença de **datas truncadas**, não de instantes | `H7`: `−41` (antes `−40`); próxima revisão `69d → 68d` com o freio inteiro |
| 10 | `insights_service.dart` | alerta de streak passa a usar `streakDetalhado.emRisco` e interpola `pisoMinutosStreak` | `I1`: "Streak de 4 dias… **15 minutos**"; `I2`: sessão de 5 min não cala mais o alerta |

**V1 VERIFY — antirregressão da suíte antiga.** Reexecutados no harness os casos da suíte existente
que as correções poderiam atingir: 10 de `gamificacao_service_test`/`streak_piso_minutos_test`
(bônus `20`/`40`/`0`, monotonia, badges não revogadas, `horas-50`), 3 de `insights_service_test`
(streak em risco, insight positivo, baixo desempenho) e a contagem de dimensões de
`export_estrela_test`. **Todas continuam verdes** — nos cenários da suíte antiga a semana anterior
nunca tem os 5 dias exigidos pelo congelamento, então `picoComCongelamento == streakPico`, e sem
chave órfã as dimensões não ganham linha.

---

# 4. RELATÓRIO DE BUGS, INCONSISTÊNCIAS E OTIMIZAÇÕES

## 4.1 Corrigidos e verificados nesta rodada (10)

**#1 — ALTO · Gamificação · `stats_service.dart` / `gamificacao_service.dart`**
`streakPico` contava só dias colados, enquanto o contador exibido (`streakDetalhado`) honra o
congelamento. Quem descansa 1 dia por semana — exatamente o comportamento que o congelamento
existe para premiar — via **39 dias de chama com pico de 6**: badges "Semana cheia" (7) e "Mês de
ferro" (30) **inalcançáveis para sempre** e bônus de XP congelado em 60. Corrigido com
`streakPicoComCongelamento(registros, hoje)`, monótono e 100% derivado; só dias que encerram um run
cru entram como candidatos (custo ≈ O(runs × tamanho do streak)).
*Efeito na massa de teste:* pico `6 → 35`, XP `5954 → 6244`, nível `4 → 5`.
> **Decisão de produto necessária:** o texto da badge diz "30 dias **seguidos**" e agora ela acende
> com 35 dias de estudo + 6 domingos protegidos. Duas saídas coerentes: (a) ajustar o texto para
> "30 dias de chama"; (b) manter o pico cru só nas badges e usar o novo pico apenas no bônus de XP.
> Escolha (a) foi assumida no código; reverter a badge é uma linha.

**#2 — ALTO (perda irreversível) · Import · `exportar_screen.dart` + serviços de export/import**
"JSON — backup de UM ambiente" gera arquivo versão 1 com `leituras`, `resumos` e `planejamento`
vazios **por escopo**. O fluxo "Validar e importar" (substituir) executava
`substituirTudo([])`/`substituir({})` nessas coleções → apagava a lista de leituras, todos os
resumos e o cronograma semanal. O diálogo avisa "tudo será apagado", mas o resumo exibido diz
"0 leituras, 0 resumos", o que induz ao erro. Corrigido: backup parcial ganha `escopo: 'ambiente'`,
`BackupImportado.parcial` expõe isso e a tela recusa a substituição orientando o modo mesclar.
Backup completo e backups legados (sem o campo) seguem substituíveis.

**#3 — MÉDIO-ALTO · FSRS · `revisao_service.dart`**
`estabilidade ≤ 0` ou não finita (backup editado à mão, migração futura, bug de gravação) zerava o
denominador de `R(t)=1/(1+t/9S)` e explodia o freio `pow(S,-w9)` → `NaN` → `NaN.round()` lança
`UnsupportedError`. Pior: em `RevisaoUseCase.concluir` a revisão **já foi salva como feita** antes
do cálculo, então a cadeia morria em silêncio e a UI só mostrava erro. Corrigido com queda para a
semente; `dificuldade` não finita idem.

**#4 — MÉDIO · Hierarquia · `topicos_screen.dart`**
Ciclo em `parentId` (`a→b→a`, ciclo de 3, ou auto-pai) — que `Topico.fromJson` aceita sem validar —
fazia os tópicos envolvidos **desaparecerem da tela** continuando gravados no Hive (a poda de órfãos
só considerava pai inexistente). Corrigido com controle de emissão única, que também elimina o risco
de recursão infinita.

**#5 — MÉDIO · XP caía ao excluir matéria (`repositorios.dart` + `dashboard_providers.dart`)**
Registros sobrevivem à cascata (promessa de UI), mas `pesoPorMateria` era montado só das matérias
vivas, e `xpPonderado` degrada matéria desconhecida para ×1,0. Excluir uma matéria peso 5 tirava
**536 XP** (−9%) na massa de teste, **rebaixando de nível 5 para 4** — contrariando a monotonia que
o próprio serviço documenta. Corrigido explorando o **tombstone** que `Materia` já tem: o registro
continua no box, então `MateriasRepositorio.pesosHistoricos()` recupera o peso histórico sem
ressuscitar a matéria na UI e sem persistir nada de novo.

**#6 — MÉDIO · Excluir tópico não cascateava (novo `application/topico_use_case.dart`)**
Matéria e aula tinham use case com cascata; tópico era `repositorio.remover(id)` cru. A revisão
pendente do tópico ficava **viva, agendada e notificando**, com a cadeia FSRS gerando sucessoras
para algo inexistente; filhos desabavam para a raiz e arestas de pré-requisito ficavam penduradas.
Criado `TopicoUseCase` espelhando `AulaUseCase`: cancela e remove revisões pendentes, **reparenta os
filhos para o avô** (hierarquia encolhe um nível em vez de desabar), limpa os pré-requisitos que
citavam o excluído e preserva revisões feitas e registros. `Topico.copyWith` ganhou `limparParent`
(mesma convenção de `Materia.limparMinutosAlvo`) porque `parentId: null` caía no `??`. O menu
"Excluir todos os tópicos" passou a usar a mesma cascata.
> Decisão registrada: o `topicoId` pendurado nos registros **não** é limpo — é log histórico, e todos
> os consumidores (mapa, fronteira, métricas) já filtram por id existente. O export ganhou dimensão
> sintética (#7) para o único consumidor que não filtrava.

**#7 — MÉDIO · Export estrela com fatos órfãos (`export_service.modeloEstrela`)**
Após excluir matéria: 71 linhas em `fato_registros.csv` referenciando 5 `materia_id` contra 4 em
`dim_materia.csv` → linha em branco no relacionamento do Power BI e medida que não soma por
dimensão. Corrigido com linha sintética por chave presente só no fato
(`(matéria excluída)` / `(tópico excluído)`, `arquivada = true`, demais colunas em branco para não
inventar dado). Sem chave órfã, nada muda.

**#8 — MÉDIO · WCAG 2.2 AA (contraste medido, não estimado) · `app_theme.dart`**
Razões calculadas sobre os fundos reais (`page #0F1115`, `surface #1B2130`):

| Token | vs page | vs surface | Uso | Veredito |
|---|---|---|---|---|
| ~~`critico #D03B3B`~~ | 3,93 | **3,34** | texto 11-12 px (`card_desempenho:97`, `card_prontidao:115`, `card_alertas:41/50`, `mapa:424`) | **falhava 1.4.3** |
| **`critico #E06A63`** (novo) | 5,77 | **4,91** | mesma tinta de texto/ícone/barra | **OK** |
| **`criticoSuperficie #D03B3B`** (novo) | — | — | fundo do botão destrutivo; rótulo branco = **4,80** | OK |
| `chama #D95926` | 4,87 | 4,14 | ícone da chama | OK (1.4.11, 3:1) |
| `safiraClara #3D7BD9` | 4,53 | 3,85 | preenchimento do heatmap | OK (gráfico) |
| `bom #0CA30C` | 5,63 | 4,79 | texto de status | OK (folga de 0,29) |
| `atencao #FAB219` | 10,30 | 8,76 | texto de status | OK |
| série `#008300` (verde) | 3,82 | 3,25 | fatia de gráfico | OK (3:1); falharia como texto |
| `inkPrimary/inkSecondary/muted` | 18,90 / 11,87 / 7,18 | 16,07 / 10,09 / 6,10 | corpo e rótulos | OK com folga |

Foi preciso separar em dois tokens porque a mesma cor servia como tinta sobre fundo escuro **e**
como fundo de botão: clarear para 4,91:1 como texto derrubaria o rótulo branco do botão para
3,26:1. `gridline`/`baseline` em 1,28–1,60:1 são decorativos (isentos), mas a linha de base do eixo
ganharia legibilidade em ≥3:1 — não alterado. Legenda do donut já estava correta (ponto colorido +
texto em `inkSecondary`).

**#9 — BAIXO · `inDays` truncava a antecipação (`revisao_use_case.dart`)**
`diasDeAtraso` vinha de `DateTime.now().difference(agendada).inDays`, e `inDays` trunca em direção
ao zero: concluir 3 dias antes às 20h dava `−2`. O freio de antecipação saía sistematicamente um dia
mais fraco. Corrigido comparando datas truncadas — no cenário `H7` a antecipação virou `−41` (era
`−40`) e a próxima revisão caiu de `69d` para `68d`.

**#10 — BAIXO · Alerta de streak com régua própria (`insights_service.dart`)**
Usava `streakAtual` (sem piso de minutos) e `minutosNoDia > 0`, então anunciava um número diferente
do da chama e uma sessão de 1 minuto calava o alerta sem sustentar o streak; ainda citava
"25 minutos" com o piso real em 15. Passou a usar `streakDetalhado.emRisco` (mesma régua do
dashboard) e a interpolar `StatsService.pisoMinutosStreak`.

## 4.3 Achados abertos (sem correção nesta rodada)

11. **Sessão de 0 minuto ao concluir revisão com questões** — `revisoes_screen` não pergunta o tempo
    e o use case usa `minutos: 0`. A sessão fantasma entra em `registros.length` (badge "10 sessões")
    e zera o "mínimo diário" do resumo se for a única do dia. Não corrigido por ser **decisão de
    produto**: perguntar o tempo do recall, assumir um valor padrão, ou marcar a sessão para
    excluí-la das contagens de constância. (O impacto no streak já foi neutralizado em #10.)
12. **Backup "completo" não inclui `Configuracoes`** — meta semanal, hora de notificação e ambiente
    ativo se perdem ao restaurar em instalação nova. Adicionar como campo tolerante (versão 1).
13. **Sem transação entre boxes no "substituir"** — 10 `substituirTudo` sequenciais; falha no meio
    deixa estado misto irreparável. Mitigação baixo custo: gerar `jsonCompleto` do estado atual e
    persistir como snapshot de rollback antes de começar.
14. **Sem UI para reparentar tópico** — o diálogo de edição só altera nome e notas; mover um
    subtópico exige excluir e recriar. Com a cascata de #6 isso agora **remove as revisões pendentes
    do tópico**, então a falta da UI ficou mais cara: vale adicionar um seletor de pai no diálogo.
15. **Goldens desatualizados** — `test/goldens/01_dashboard.png` e `03_revisoes.png` foram gravados
    antes das correções #1 (badges/XP) e #8 (tom do vermelho crítico). Regravar com
    `flutter test --tags screenshots --update-goldens`. Não quebra `flutter test` (tag isolada).
16. **Validar no ambiente local** — `flutter test` (60 arquivos antigos) e `flutter test test/uat`.
    Os 4 pontos de atrito possíveis já foram reexecutados no harness (§V1), mas a compilação sob
    `flutter_test` e as camadas Riverpod/Hive só fecham na sua máquina.

## 4.4 O que passou sem ressalva (vale registrar)

- **Zero divisão por zero** em toda a superfície de rendimento/prontidão/ritmo: ausência de dado
  devolve `null`, nunca `0%`, `NaN` ou infinito.
- **Invariantes de modelo** aplicadas na fábrica, valendo também para import
  (`acertos ≤ questoes`, minutos em `[0, 960]`, páginas não negativas, peso ≥ 1).
- **Parser de backup** rejeita 8 de 8 malformações testadas com `FormatException` — nunca importa
  parcial em silêncio.
- **CSV injection (CWE-1236)** neutralizada nos três exports, inclusive nas dimensões do modelo estrela.
- **Anti-farm de XP** funcionando: teto de 3 revisões com bônus por dia e piso de 15 min/dia no streak.
- **Estado degenerado sem exceção**: excluir todas as matérias mantém dashboard, heatmap, streak e
  export operando; `prontidao` devolve `null` em vez de número inventado.

---

# 5. ONDA 2 — Execução real no Flutter + funcionalidades novas (30/07/2026)

## 5.1 O limite da onda 1 caiu

A ressalva da onda 1 era não ter Flutter SDK: Riverpod, Hive e widgets ficaram
só na auditoria estática. Isso acabou. **Flutter 3.44.8 / Dart 3.12.2**
(exatamente a versão do `pubspec.yaml`) provisionado por `git clone --depth 1`
do canal stable + bootstrap dos artefatos de engine.

Detalhe operacional que vale registrar para quem repetir: **`flutter test` não
roda direto na pasta montada** (o sistema de arquivos bloqueia a remoção de
`ios/Flutter/ephemeral/`, e a ferramenta aborta). A saída é espelhar o repo para
um diretório local e rodar lá:

```bash
rsync -a --delete --exclude .git --exclude build --exclude .dart_tool \
      --exclude ios --exclude android --exclude windows.disabled \
      /caminho/app_estudos/ ~/app/
cd ~/app && flutter pub get && flutter analyze --no-pub && flutter test
```

### Resultado da execução (real, não estimado)

| Suíte | Testes | Estado |
|---|---:|---|
| `test/*.dart` (unit + widget + segurança) | 527 | verdes |
| `test/uat/*.dart` (aceitação, onda 1) | 88 | verdes |
| `test/screenshots_test.dart` (goldens, tag `screenshots`) | 6 | verdes |
| **Total** | **621** | **verdes** |
| `flutter analyze --no-pub` | — | **No issues found** |

Baseline antes de qualquer mudança desta onda: 424 + 88 verdes e **só os 2
goldens falhando** (1,32% de pixel), exatamente a previsão da onda 1 — as
correções de badge/XP/cor tinham mudado o dashboard. Goldens regravados.

## 5.2 Funcionalidades novas

Orquestração em Opus 5; execução delegada a agentes Sonnet 5 em paralelo, com
arquivos disjuntos e verificação obrigatória por execução em cópia própria.

### Caderno de Erros (`lib/features/caderno/`, `lib/domain/caderno_erros_service.dart`)
A maior lacuna do app para concurso: ele contava acertos, mas jogava fora **a
questão**. Contagem não ensina; reencontrar o mesmo item dias depois, sim.

- `QuestaoErrada`: enunciado, resposta marcada × correta, **por que errei**,
  banca, ano, órgão, origem (manual / simulado / sessão), estado FSRS.
- Agendamento **reusa `RevisaoService.proximoPassoFsrs`** — mesma curva das
  revisões, sem um segundo motor de espaçamento para manter sincronizado.
- Sai do caderno com **2 acertos seguidos em datas diferentes** (um acerto
  isolado pode ser chute de 20% num item de 5 alternativas).
- Fila do dia ordenada por peso do edital → atraso → nº de erros.
- Card no dashboard: quantas vencem hoje + taxa de recuperação.
- 29 testes (23 de domínio/providers, 6 de widget).

### Desempenho por banca (`lib/domain/banca_service.dart`, `lib/data/models/bancas.dart`)
Banca virou dimensão de primeira classe em sessões e simulados, com
**normalização** (`CESPE`, `cespe`, `CESPE/CEBRASPE` → `CEBRASPE`) — sem isso o
ranking fragmentaria em três linhas de 10 questões no lugar de uma de 30.

- Ranking por taxa, excluindo bancas com menos de 10 questões (ordenar ruído
  induz decisão errada), com rodapé dizendo quantas ficaram de fora.
- Matriz banca × matéria e `pontoFraco`: "Você acerta 52% em Direito
  Constitucional na CEBRASPE — 84 questões". É a leitura que a taxa geral
  esconde: 80% na FCC com 55% na CEBRASPE não é problema de conteúdo.
- 25 testes.

### Edital verticalizado (`lib/features/edital/`, `lib/domain/edital_service.dart`)
Horas estudadas não dizem se o edital acabou. Cobertura, sim.

- Cada tópico recebe uma situação: **intocado / estudado / frágil / dominado**
  (frágil = Elo confiável abaixo de 0,6; mesmo limiar do desbloqueio do mapa).
- Cobertura ponderada por **peso da matéria × peso do tópico** — um tópico peso 5
  intocado pesa mais que cinco de peso 1.
- "Próximos buracos" ordenados por esse custo, com a conta exposta na tela
  (`peso 5 × tópico 5 = 25`).
- Sem tópico cadastrado devolve `null`, não 0% — edital não cadastrado não é
  edital atrasado.
- 16 testes.

### Prova cronometrada (`lib/features/simulados/prova_screen.dart`, `lib/domain/prova_service.dart`)
Simulado deixou de ser só o registro do resultado.

- Setup (nome, banca, nº de questões, duração, faixas de questões por matéria),
  cronômetro regressivo, folha de respostas, correção por gabarito.
- Sobrevive a fechar o app: relógio de parede persistido em Hive, mesma técnica
  do cronômetro de estudo — não `Stopwatch` em memória.
- Ao finalizar, alimenta o resto do app de uma vez: grava o `Simulado`, cria as
  `QuestaoErrada` das erradas (com `origem: simulado`) e um `RegistroHora` de
  prática com o tempo real gasto e a banca.
- IDs determinísticos (`execucaoId-numeroDaQuestao`): corrigir duas vezes faz
  upsert, não duplica.
- 34 testes.

## 5.3 Decisões de produto aplicadas

| Decisão | Escolha | Consequência declarada |
|---|---|---|
| Revisão concluída com questões e sem tempo | Crédito padrão configurável, `Configuracoes.minutosPadraoRevisao = 10` | **Infla o total de horas em 10 min × revisões.** É estimativa, não medição. `0` desliga e volta ao comportamento antigo. |
| Badge de streak com congelamento | Texto ajustado | "7/30 dias **de chama acesa**" no lugar de "dias seguidos" — a badge volta a ser alcançável para quem descansa 1 dia por semana. |

## 5.4 Defeitos encontrados nesta onda (todos corrigidos)

**#17 — MÉDIO · Glifos `✓`/`✗` viravam caixa vazia · `card_rankings.dart`**
Só apareceu ao **renderizar a tela**: "Acertos por matéria" mostrava
`102▯ 18▯ · 85%`. Roboto não cobre U+2713/U+2717 e o CanvasKit da build web não
faz fallback de fonte — e o app é publicado na web. Trocado por
`102/120 · 85%`, o mesmo formato do card de desempenho (some o tofu e some
também a segunda gramática para o mesmo dado). Confirmado no golden novo.

**#18 — MÉDIO · "100% cobertos" com 1 tópico cadastrado · `card_edital.dart`**
O primeiro render do card do edital exibiu **100%** porque o único tópico do
cenário estava dominado. Tecnicamente certo, na prática perigoso: num edital de
centenas de itens, `100%` sem denominador é falsa segurança. O card passou a
exibir sempre a base: **"14% de 7 tópicos do edital"**.

**#19 — BAIXO · Arquivo binário dentro de `lib/`**
`lib/application/~$pico_use_case.dart` (162 bytes, lock do Microsoft Office
criado ao abrir `topico_use_case.dart` no Word). Removido, e `~$*` entrou no
`.gitignore` para não voltar.

**#20 — BAIXO · Colisão de nome entre providers**
Dois agentes criaram `bancasUsadasProvider` em bibliotecas diferentes
(`ambiguous_import`, erro de compilação). O do caderno virou
`bancasDoCadernoProvider` — escopos de fato diferentes: um olha só o caderno,
o outro agrega sessões + simulados.

**Verificação de contraste dos elementos novos:** medida sobre os pixels do
golden, não estimada. Botão primário da prova: fundo `#B0C6FF`, rótulo
`#152E60` → **7,77:1** (AA e AAA). Os tokens novos usados nos cards são os já
homologados no §4.2.

## 5.5 Cobertura visual permanente

`test/screenshots_test.dart` (tag `screenshots`, fora do `flutter test` padrão)
ganhou 3 capturas: `04_caderno_erros.png`, `05_edital.png`, `06_prova.png`, e o
seed passou a ter edital com 7 tópicos em situações diferentes e caderno com 4
questões. Regravar após mudança visual intencional:

```bash
flutter test --tags screenshots --update-goldens
```

## 5.6 Pendências

1. **`Configuracoes` continua fora do backup** (achado #12 da onda 1): meta
   semanal, hora do lembrete e agora `minutosPadraoRevisao` se perdem ao
   restaurar em instalação nova.
2. **Execução de prova em andamento não entra no backup** — decisão deliberada
   (estado efêmero preso ao relógio local), mesmo tratamento do cronômetro.
3. **Sem transação entre boxes** no import "substituir" (achado #13).
4. **Cascata do caderno**: excluir matéria/tópico deixa `QuestaoErrada` com
   vínculo pendurado. A UI já degrada para "—" e o enunciado é conteúdo caro
   escrito pelo usuário, então preservar foi deliberado — mas falta a tela de
   "questões órfãs" para reatribuir.
5. **Sem UI para reparentar tópico** (achado #14) — agora mais caro, porque a
   cascata nova remove as revisões pendentes do tópico excluído.
6. **Aba Estatísticas do caderno** ainda não expõe `porBanca`/`porTopico`, que o
   serviço já calcula.
