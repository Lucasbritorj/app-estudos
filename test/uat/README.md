# Suíte de UAT (`test/uat/`)

Testes de aceitação de ponta a ponta sobre a **camada de domínio real** (`lib/domain`,
`lib/data/models`), com massa fake determinística. Complementam a suíte unitária da raiz de
`test/`: aqui o foco é jornada de usuário, borda destrutiva e coerência entre módulos.

```bash
flutter test test/uat            # 89 casos
flutter test test/uat/uat_fsrs_test.dart
```

| Arquivo | Cobre |
|---|---|
| `_massa_fake.dart` | duas fixtures determinísticas, mesma âncora `hoje = 2026-07-29`. **Curta** (`construirMassa`, `Random(42)`, 60 dias): 5 matérias, 9 tópicos em 2 níveis, 3 aulas, 71 registros, 11 revisões. **Longa** (`construirMassaLonga`, `Random(4242)`, 120 dias): mesmas entidades, 148 registros em 99 dias (abr–jul), 21 revisões, 6 dias abaixo do piso |
| `uat_massa_longa_test.dart` | invariantes que só o horizonte de 4 meses pega: MoM encadeado, piso rejeitando dia fraco, monotonia do XP, determinismo da seed |
| `uat_massa_ciclo_test.dart` | carga inicial, horas líquidas, MoM/YoY, desempenho, streak, XP, prontidão, fila de revisão |
| `uat_fsrs_test.dart` | cadeia FSRS-lite, lapso, antecipação, atraso, teto, retenção-alvo, estado corrompido |
| `uat_rendimento_test.dart` | divisão por zero, `acertos ≤ questoes`, ponderação, janela de recência, páginas |
| `uat_streak_test.dart` | piso de minutos, congelamento, recuperação, virada de mês/ano, pico |
| `uat_destrutivo_test.dart` | cascata de matéria/aula, órfãos nos agregados, export com fantasma, wipe total |
| `uat_hierarquia_test.dart` | árvore de tópicos, órfãos, ciclo em `parentId`, DAG de pré-requisitos, 500 níveis |
| `uat_import_export_test.dart` | round-trip JSON, rejeições do parser, CSV injection, ZIP estrela, backup parcial |
| `uat_revisoes_em_dia_test.dart` | concluir revisão **com** e **sem** informação e o efeito no dashboard |
| `uat_insights_test.dart` | régua do alerta de streak (mesmo número da chama, piso interpolado da constante) |
| `uat_regressao_pico_streak_test.dart` | antirregressão das expectativas da suíte antiga afetadas pela correção do pico |

**Execução.** Verificados com `flutter test` real (Flutter 3.44.8 / Dart 3.12.2) — 88 casos
verdes junto com a suíte completa do repo (621 no total). Quatro arquivos transcrevem lógica
que vive dentro de widget ou use case (indicado no cabeçalho de cada um, com arquivo:linha de
origem); ao mexer nesses pontos do app, atualizar a transcrição junto.

**Suítes irmãs criadas na onda 2** (ficam na raiz de `test/`, não aqui): `caderno_erros_test`,
`caderno_screen_test`, `banca_service_test`, `banca_form_test`, `edital_service_test`,
`edital_screen_test`, `prova_execucao_test`, `prova_screen_test`.
