# Roadmap — app_estudos

**Este arquivo é a fonte de verdade do estado do projeto.** Planos e relatórios
de ondas encerradas vivem em [`docs/historico/`](docs/historico/README.md) e
descrevem o passado — se algum deles contradiz este arquivo, este vence.

Legenda de esforço: **P** = até meio dia · **M** = 1-3 dias · **G** = 1-2 semanas.

---

## 0. Estado em 10/08/2026

| Campo | Valor | Como conferir |
|---|---|---|
| Branch | `main`, sincronizada com `origin/main` @ `f7d82bf` | `git status -sb` |
| Remote | `https://github.com/Lucasbritorj/app-estudos.git` | `git remote -v` |
| Working tree | limpa | `git status --porcelain` |
| Commits | 60 | `git rev-list --count --all` |
| Código | 27.373 LOC em `lib/` | `find lib -name '*.dart' \| xargs wc -l` |
| Testes | 93 arquivos · 17.160 LOC · **858 declarações** `test(`/`testWidgets(` | `grep -rhoE '\b(test\|testWidgets)\(' test/ \| wc -l` |
| Goldens | 19 telas (falta `onboarding`) | `flutter test --tags screenshots` |

> **Contagem estática.** As 858 declarações foram contadas por `grep`, não por
> execução — `flutter test` não roda no ambiente onde este arquivo foi
> atualizado. Números de *aprovação* (`X testes verdes`) só devem ser escritos
> aqui depois de uma execução real; o histórico deste arquivo já afirmou "740
> testes verdes" muito depois de o número ter mudado.

### Verificação de pré-voo

```bash
flutter analyze
flutter test --exclude-tags screenshots
flutter test --tags screenshots          # goldens, job separado no CI
```

## 0b. Achados do motor de XP — todos fechados

| Achado | O que era | Estado |
|---|---|---|
| **M-02** | `xpPonderado` sem teto: cada conclusão de revisão com questões gravava `minutosPadraoRevisao` que ninguém cronometrou, inflando horas, XP base, streak e heatmap sem limite | **Fechado** em `d79b89c` (04/08) — opção B, teto diário espelhando `maxRevisoesComBonusPorDia` |
| **M-03** | Conclusão antecipada tratada como intervalo pleno no FSRS | **Fechado**, 2 call sites conferidos |
| **M-04** | FSRS ignorava a nota da própria revisão | **Fechado**, coberto por UAT-H1/H2 |
| *(extra)* | Espelho UAT `Mundo` derivou da produção — nasceu com `minutos = 0` e ficou cego justamente na parcela do M-02 | **Fechado** no mesmo commit; hoje lê `const Configuracoes().minutosPadraoRevisao`, a mesma fonte do use case |

Como o teto funciona: as 3 primeiras conclusões do dia creditam
`minutosPadraoRevisao`; da 4ª em diante a sessão entra com 0 min. Questões e
acertos **nunca** são descartados — o corte é só no tempo não cronometrado.
Tempo informado (`minutos != null`) passa inteiro, porque é medição.

Decisão completa, alternativas A/C descartadas e o porquê:
[`docs/historico/PLANO_M02_M03_M04.md`](docs/historico/PLANO_M02_M03_M04.md),
seção "Execução".

### Risco residual aceito (M-02r)

O teto limita o **XP**, não o **streak**. `StatsService.pisoMinutosStreak` é 15
min/dia e o teto rende `3 × minutosPadraoRevisao`. Com o padrão de 10 min isso
dá 30 min/dia, acima do piso; no seletor (0/5/10/15/20/30) só o valor `0` deixa
o dia abaixo do piso — `5` empata em 15 e ainda acende a chama.

Consequência: concluir 3 revisões/dia continua sustentando streak e heatmap sem
estudo cronometrado. O que a opção B garantiu é que o ganho **não escala** — é
constante e pequeno, em vez de linear no número de conclusões. Fechar de vez
exige a opção C (campo em `RegistroHora` + migração de schema), fora de escopo
por ora.

Segunda divergência menor, deliberada: `revisoesConcluidasNoDia` conta **todas**
as conclusões do dia, inclusive as que não creditaram minuto nenhum (conclusão
sem questões não grava `RegistroHora`). Quem fechar 3 revisões sem questões e
depois uma com questões recebe 0 min na quarta. É mais conservador do que o
necessário e afeta pouca gente; registrado para não ser redescoberto como bug.

---

## 2. Bugs abertos

| # | Problema | Onde | Esforço |
|---|---|---|---|
| B16 | Prova em andamento continua fora do backup (deliberado — estado preso ao relógio local), mas não há como exportá-la nem avisá-la ao trocar de aparelho. | `export_service.dart` | M |
| — | *(B20 resolvido: `agoraProvider` de uma linha + 1 call site.)* | | |

## 3. Qualidade e infraestrutura

| # | Lacuna | Esforço |
|---|---|---|
| Q3 | **Sem tema claro** (dark-only, sem `ThemeMode`). O Lumina já é tokenizado: é trabalho de paleta, não refatoração. | M |
| Q5 | **Sem desfazer** fora da importação. Excluir matéria/tópico/questão continua irreversível com só um diálogo. Agora que `BackupUseCase` existe, dá para generalizar o padrão de snapshot. | M |
| Q6 | Goldens cobrem **19 telas**. Falta só `onboarding` (fluxo multi-passo, precisa de um golden por passo). | P |
| Q9 | Sem teste de integração ponta a ponta (`integration_test`) — a suíte é unit + widget isolado. | M |

## 4. Funcionalidades sugeridas

| # | Funcionalidade | Racional | Esforço |
|---|---|---|---|
| F2 | **Importar questões em lote** (CSV/planilha) | Quem já mantém caderno no Excel migra sem redigitar. `xlsx_reader` já existe. | M |
| F3 | **Relatório PDF semanal automático** | Recorte segunda→hoje no disco em `85c67aa` (`StatsService.registrosNaSemanaAte`). Falta o agendamento. | P (resto) |
| F4 | **Cronograma dia-a-dia até a prova** | A prontidão já projeta o domínio na data e o edital já mede cobertura — falta virar plano executável. Peça que amarra planejamento, edital e revisão. | G |
| F5 | **Exportar caderno para Anki** | Boa parte dos concurseiros já vive no Anki; exportar em vez de competir aumenta adoção. | M |
| F6 | **Notificação acionável** ("Acertei"/"Errei" direto do lembrete) | Revisão feita no semáforo é revisão feita. `flutter_local_notifications` já suporta actions. | M |
| F7 | **Nota de corte** vs prontidão projetada | Transforma "70% de prontidão" em "acima/abaixo do corte do ano passado". | M |
| F8 | **Backup automático agendado** | Hoje depende de o usuário lembrar. O `BackupUseCase` já sabe serializar tudo. | M |
| F10 | **Lei seca / artigo lido** | Direito se estuda por artigo. Encaixa no modelo de Leituras. | M |
| F11 | **Sincronização multi-dispositivo** | `atualizadoEm` e tombstones já preparam isso. Falta o transporte — e a decisão de produto (servidor, custo, privacidade) que quebra o "100% offline". | G |
| F12 | **Ciclo de estudos rotativo clássico** | O app tem ciclo por utilidade (Elo/peso); o rodízio tradicional é o que muita gente espera encontrar. | M |

---

## 5. Planejamento

### Curto prazo — o que resta verificar

Os dois bloqueios do roadmap anterior (repo sem `remote`; deploy web parado)
foram resolvidos: o remote existe e `main` está sincronizada, e o deploy foi
religado em `83f564e` → `6f471c3` → `dd5c7f2`.

**Confirmado por execução em 26/08/2026 (não só por existência de YAML):**

1. **CI verde no runner.** Run [32878953019](https://github.com/Lucasbritorj/app-estudos/actions/runs/32878953019) (`CI`, `85c67aa`, success) e run [32879139972](https://github.com/Lucasbritorj/app-estudos/actions/runs/32879139972) (`Headers de produção`, success).
2. **`Permissions-Policy` viva em produção.** `curl -sI https://app-estudos-neon.vercel.app` em 26/08/2026 20:37 -03 devolveu `permissions-policy: camera=(self), microphone=(), geolocation=(), payment=()` + CSP + HSTS.

Não há mais item de pré-voo aberto nesta seção.

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
5. **M-02r — opção C** (marcar a sessão como gerada por revisão), se o vetor de streak virar problema real. Único item que mexe em schema de `RegistroHora`.
6. **F11 — sincronização multi-dispositivo**, por último: o único item que quebra a premissa "100% offline" e exige decisão de produto antes de decisão técnica.

---

## 6. Se houver pouco tempo

Pré-voo CI e `Permissions-Policy` reconfirmados em 26/08 (runs 32878953019 e
32879139972; header vivo em `app-estudos-neon.vercel.app`). F3 recorte
semanal já está no disco (`85c67aa`); o que falta de F3 é agendamento (vizinho
de F8). Próximo P: **Q6 (golden do onboarding)**.
---

## 7. Manutenção deste arquivo

Regras que existem porque já foram violadas:

- **Número de teste só entra aqui depois de `flutter test` rodar.** Contagem
  estática é rotulada como tal.
- **Bloqueio resolvido sai do arquivo no mesmo commit que o resolve.** Este
  roadmap afirmou "o repositório não tem `git remote`" por dias depois de o
  remote existir.
- **Plano encerrado vai para `docs/historico/`.** Um plano que continua na raiz
  compete com este arquivo pela posição de fonte de verdade — e perde, mas só
  depois de alguém perder tempo.
