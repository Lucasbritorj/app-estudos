# Histórico — artefatos de ondas encerradas

**Nada aqui descreve o estado atual do projeto.** O estado atual está em
[`../../ROADMAP.md`](../../ROADMAP.md).

Estes documentos são o registro de *o que foi decidido e por quê*. Vários foram
escritos como planos e congelaram no tempo verbal do planejamento — texto do
tipo "aguardando autorização", "furo em aberto" ou "PARADA" descreve o momento
em que o documento foi escrito, não hoje. Um deles (`PLANO_M02_M03_M04.md`) já
induziu uma tentativa de re-executar trabalho concluído; por isso ganhou uma
seção "Execução" no fim.

Regra de leitura: **data no topo do arquivo manda.** Se o que está aqui
contradiz o `ROADMAP.md`, o `ROADMAP.md` vence.

| Arquivo | Data | O que é |
|---|---|---|
| `RELATORIO_AUDITORIA.md` | 24/07/2026 | Auditoria profunda em 3 agentes + revisor: 52 achados 5W2H com severidade (motor de métricas, dados/persistência, UX) |
| `LEDGER_DE_AUDITORIA.md` | 24/07/2026 | Ledger de rastreamento dos achados da auditoria |
| `RELATORIO_UAT_2026-07-29.md` | 29/07/2026 | UAT sobre massa sintética — comportamento observado do dashboard |
| `DIAGNOSTICO_2026-08-03.md` | 03/08/2026 | Diagnóstico de estado por protocolo graph-loop (FASE 0→3), verificado por execução |
| `PLANO_2026-08-03.md` | 03/08/2026 | Plano da onda derivado do diagnóstico acima |
| `LEDGER_EXECUCAO.md` | 03/08/2026 | Ledger de execução da mesma onda |
| `PLANO_M02_M03_M04.md` | 03/08 → **04/08/2026** | Plano dos achados M-02/M-03/M-04 do motor de XP. **Executado** (opção B, commit `d79b89c`) — ver a seção "Execução" no fim do arquivo |
| `PLANO_ONDA_P1.md` | — | Plano da onda P1 |
| `PLANO_D01.md` | — | Plano do achado D-01 (restauração destrutiva de backup) |
| `PLANO_DISPOSE.md` | — | Plano do vazamento de `TextEditingController` |
| `PLANO_A11Y_DASHBOARD.md` | — | Plano de acessibilidade do dashboard |
| `ENTREGAS_ATE_2026-08-03.md` | até 03/08/2026 | Registro das entregas (Q1, B1–B19 e ondas de 31/07 e 03/08), extraído do `ROADMAP.md` em 10/08 |

## Por que arquivar em vez de apagar

Os comentários de decisão são o maior ativo deste repositório — o `README.md`
diz isso explicitamente sobre o código, e vale para os documentos. Apagar um
plano apaga o *porquê* de uma escolha e obriga a redescobri-lo na próxima
dúvida. O que não pode acontecer é um plano encerrado competir com o
`ROADMAP.md` pela posição de fonte de verdade — daí a separação física.
