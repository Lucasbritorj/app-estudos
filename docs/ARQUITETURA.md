# App_estudos — ESPECIFICAÇÃO TÉCNICA E ARQUITETURA

> Documento denso para ingestão por LLM/RAG. Grão: arquivo → classe → função → fórmula.
> Produto: **Meu Caminho Aprovado**. Pacote: `app_estudos` v1.0.0+1.

## 1. Visão Geral & Propósito do Sistema

- **Objetivo Central:** app Flutter *local-first* (zero backend/rede) que converte sessões de estudo para concurso em métricas acionáveis — revisão espaçada FSRS-lite, domínio Elo por matéria/tópico, cobertura de edital, prontidão projetada para a data da prova e export BI.
- **Stack Tecnológica:** Dart SDK `^3.12.2` / Flutter `3.44.8` (fixado no CI) · Riverpod `^3.3.2` (`Notifier`/`Provider`) · Hive CE `^2.19.3` (doc-store `Box<Map>` JSON, sem codegen) · fl_chart `^1.2.0` · intl `0.20.2` · uuid · flutter_local_notifications `^22` + timezone · pdf · archive + xml (leitor `.xlsx` próprio) · file_selector · image_picker · share_plus · flutter_staggered_grid_view. Deploy web estático (Vercel + CanvasKit).
- **Fluxo de Dados:**

```
UI (features/*Screen)
  → Riverpod Notifier (data/repositories/*)            [projeção em memória]
  → Hive Box<Map> JSON                                  [fonte persistida]
  ↑
  └─ Provider derivado (features/*_providers.dart)      [memoização de agregados]
       ← domain/*Service (funções PURAS, sem Flutter/Hive)
       ← application/*UseCase (orquestração multi-repo + notificações)

Entrada: RegistroHora (form|cronômetro|prova) · Aula · Topico (edital colado) · .xlsx
Processo: invariantes na factory do modelo → serviço puro → agregado memoizado
Saída: dashboard · fila de revisão/caderno · CSV/CSV-BI/modelo-estrela.zip · JSON backup
```

**Invariante arquitetural:** `domain/` nunca importa Flutter, Hive ou Riverpod. `data/models/*` valida na *factory* (borda única), então import de backup adulterado não consegue gravar estado impossível.

---

## 2. Mapa de Arquitetura & Módulos

### 2.1 Bootstrap e casca

| Arquivo / Caminho | Responsabilidade Única | Principais Dependências |
|---|---|---|
| `lib/main.dart` | Boot em `runZonedGuarded`; abre/migra Hive; degrada para `FalhaBootApp` se armazenamento falhar | `hive_ce_flutter`, `HiveBoxes`, `NotificacoesService`, `FalhaBootApp` |
| `lib/app.dart` | `MaterialApp` pt-BR, gate de onboarding, shell responsivo (bottom bar ↔ sidebar ≥1080px), `abaProvider` | `flutter_localizations`, `app_theme`, todas as `*Screen` |
| `lib/core/boot/falha_boot.dart` | Tela de último recurso do boot — **zero imports do app** (cores literais) | `material`, `services` (Clipboard) |
| `lib/core/theme/app_theme.dart` | Tokens: `Spacing`, `Radii`, `seriesColors`, `LuminaColors`, `StatusColors`, `LuminaElevation`, `LuminaText`, `VizColors`, `buildDarkTheme()`, `LuminaBackground`, `ConteudoCentral` | `material` |

### 2.2 `core/` — utilitários transversais

| Arquivo / Caminho | Responsabilidade Única | Principais Dependências |
|---|---|---|
| `core/notificacoes/notificacoes_service.dart` | Agendar/cancelar lembretes locais (best-effort, nunca fatal) | `flutter_local_notifications`, `timezone`, `flutter_timezone` |
| `core/utils/compartilhador.dart` | Fachada condicional de export (`io` vs `js_interop`) | — |
| `core/utils/compartilhador_io.dart` | Grava temp + compartilha caminho (Android/desktop) | `path_provider`, `share_plus` |
| `core/utils/compartilhador_web.dart` | Compartilha bytes direto (web) | `share_plus` |
| `core/utils/formatters.dart` | Formatação pt-BR (minutos, decimal com vírgula, milhar, cronômetro, plural) | `intl` |
| `core/utils/haptica.dart` | 3 canais de feedback tátil (`leve`/`celebrar`/`selecao`) | `services` |
| `core/utils/notas_ricas.dart` | Parser markdown-lite (`**b**`, `==destaque==`, `- `) | — |
| `core/widgets/avatar_cor.dart` | Bolinha de cor da entidade (`corDaSerie(slot)`) | `app_theme` |
| `core/widgets/estado_vazio.dart` | Estado vazio padrão (ícone+título+descrição+CTA) | `app_theme` |
| `core/widgets/notas_editor.dart` | Editor/preview de notas markdown-lite | `notas_ricas` |

### 2.3 `data/` — modelos, boxes, repositórios

| Arquivo / Caminho | Responsabilidade Única | Principais Dependências |
|---|---|---|
| `data/local/hive_boxes.dart` | Nomes dos 16 boxes, `openAll`, `migrar` (schema v2), `repararOrfaos`, `seedResumos` | `hive_ce_flutter`, `uuid`, models |
| `data/catalogo/catalogo_materias.dart` | 60 matérias canônicas + `siglaPara(nome)` | — |
| `data/models/ambiente.dart` | Contêiner de matérias; `geralId`, `dataProva` | — |
| `data/models/materia.dart` | Peso/questões/mínimo/intimidade/minutosAlvo + tombstone `excluidaEm` | `ambiente` |
| `data/models/topico.dart` | Hierarquia `parentId` + arestas `prerequisitos` (DAG) | — |
| `data/models/aula.dart` | PDF com `paginasLidas ≤ paginasTotais`; gatilho da cadeia de revisão | — |
| `data/models/registro_hora.dart` | Sessão de estudo (grão do fato); invariantes duras; tombstone | `bancas` |
| `data/models/revisao.dart` | Revisão agendada + estado FSRS (`estabilidade`,`dificuldade`) | — |
| `data/models/questao_errada.dart` | Item do caderno de erros com estado FSRS próprio | `bancas` |
| `data/models/execucao_prova.dart` | `ItemProva` + prova cronometrada em slot único | `ambiente`, `bancas` |
| `data/models/simulado.dart` | `ResultadoMateria` + `Simulado` (totais derivados) | `bancas` |
| `data/models/leitura.dart` | `SessaoLeitura` + `Leitura` (divisão em partes) | — |
| `data/models/resumo.dart` | Página única por matéria (sigla-tag) | — |
| `data/models/bancas.dart` | Catálogo + `normalizar()` (canônica, resolve apelidos) | — |
| `data/models/configuracoes.dart` | Preferências (intervalos, metas, lembretes, ambiente ativo) | — |
| `data/repositories/repositorios.dart` | `_HiveRepositorio<T>` genérico + 10 repositórios + `ExecucaoProvaController` + `AnexosQuestaoRepositorio` | `hive_ce`, `flutter_riverpod`, models |
| `data/repositories/configuracoes_repositorio.dart` | Slot único `config` | `hive_ce`, `configuracoes` |
| `data/repositories/planejamento_repositorio.dart` | Cronograma semanal escopado por ambiente (`semana:<id>`) | `hive_ce`, `configuracoes_repositorio` |
| `data/repositories/ambiente_filtros.dart` | Providers de escopo: `ambienteAtivo`, `materias/registros/revisoesDoAmbiente` | `flutter_riverpod`, repositórios |

### 2.4 `domain/` — regras puras (sem Flutter/Hive/Riverpod)

| Arquivo / Caminho | Responsabilidade Única | Principais Dependências |
|---|---|---|
| `domain/revisao_service.dart` | Motor **FSRS-lite** (`proximoPassoFsrs`), reancoragem, forecast, cadeia de intervalos | `dart:math`, models |
| `domain/parametros_ciclo.dart` | Constantes compartilhadas Planejamento↔Prontidão | — |
| `domain/dominio_service.dart` | Estimador **Elo** de domínio com esquecimento temporal | `dart:math`, `registro_hora` |
| `domain/planejamento_service.dart` | Diagnóstico, ciclo por utilidade marginal (mochila gulosa), fila de estudo | `dominio_service`, `parametros_ciclo` |
| `domain/prontidao_service.dart` | Projeção de prontidão semana a semana + ajuste por dispersão | `planejamento_service`, `parametros_ciclo` |
| `domain/stats_service.dart` | Toda a matemática de datas/agregação temporal + streak com congelamento | `registro_hora` |
| `domain/retencao_service.dart` | *True retention* (acerto nas revisões concluídas) | `registro_hora` |
| `domain/gamificacao_service.dart` | XP ponderado, níveis, badges (100% derivado e monótono) | `stats_service` |
| `domain/quests_service.dart` | 3 quests diárias derivadas do planejador (sem XP) | `stats_service` |
| `domain/insights_service.dart` | Rankings + recomendações "o que melhorar hoje" | `stats_service` |
| `domain/diagnostico_service.dart` | Veredito único do dia por votação de pilares | — (self-contained) |
| `domain/caderno_erros_service.dart` | Fila/agendamento/estatística do caderno de erros (reusa FSRS) | `revisao_service` |
| `domain/edital_service.dart` | Edital verticalizado: situação, cobertura ponderada, buracos | `dominio_service` |
| `domain/edital_parser_service.dart` | Parser de conteúdo programático colado de PDF | — |
| `domain/mapa_estudos_service.dart` | Grafo de conhecimento: fronteira, bloqueios, detecção de ciclo | `dominio_service`, `stats_service` |
| `domain/aula_service.dart` | Ritmo pág/h da aula e transição de conclusão | models |
| `domain/leitura_service.dart` | Divisão equilibrada de PDF + progresso/projeção | `leitura` |
| `domain/banca_service.dart` | Desempenho por banca e matriz banca×matéria | models |
| `domain/prova_service.dart` | Tempo, progresso e correção da prova cronometrada | models |
| `domain/busca_service.dart` | Busca global ranqueada, normalizada, à prova de exceção | models |
| `domain/xlsx_reader.dart` | Leitor `.xlsx` (zip+SpreadsheetML) com defesa anti zip-bomb | `archive`, `xml` |
| `domain/export_service.dart` | CSV pt-BR, CSV BI, modelo estrela, ZIP, JSON de backup | `archive`, models |
| `domain/import_service.dart` | Parser do backup JSON (falha explícita, nunca parcial) | models |
| `domain/planilha_import_service.dart` | Mapeia abas da planilha legada → domínio (ids determinísticos) | models |

### 2.5 `application/` — casos de uso (orquestração)

| Arquivo / Caminho | Responsabilidade Única | Principais Dependências |
|---|---|---|
| `application/sessao_estudo_use_case.dart` | Registro → progresso da aula → cadeia de revisão → reancoragem → notificação | `aula_service`, `revisao_service`, repositórios |
| `application/revisao_use_case.dart` | Concluir (passo FSRS), adiar, criar revisão manual | `revisao_service`, `notificacoes_revisao` |
| `application/notificacoes_revisao.dart` | Ponto único cancelar+reagendar lembrete | `notificacoes_service` |
| `application/materia_use_case.dart` | Exclusão de matéria em cascata | repositórios, `notificacoes_service` |
| `application/topico_use_case.dart` | Exclusão de tópico em cascata + `podeMoverPara` (anti-ciclo) | repositórios |
| `application/aula_use_case.dart` | Exclusão de aula em cascata (preserva registros) | repositórios |
| `application/backup_use_case.dart` | Restauração com snapshot de rollback e undo | `export_service`, `import_service` |
| `application/apagar_dados_use_case.dart` | Wipe out total (16 boxes, ordem filhos→pais) | todos os repositórios |

### 2.6 `features/` — UI (Riverpod `ConsumerWidget`)

| Arquivo / Caminho | Responsabilidade Única | Principais Dependências |
|---|---|---|
| `features/dashboard/dashboard_providers.dart` | 20+ agregados memoizados (`hojeProvider`, `agoraProvider`, resumo, prontidão, diagnóstico…) | todos os `domain/*Service` |
| `features/dashboard/dashboard_screen.dart` | Composição/masonry dos cards + estado vazio de onboarding | widgets do dashboard |
| `features/dashboard/bancas_providers.dart` | Ranking/ponto fraco por banca no ambiente ativo | `banca_service` |
| `features/dashboard/frases_do_dia.dart` | 366 frases indexadas por dia-do-ano (determinístico) | — |
| `features/dashboard/confete_leve.dart` | Overlay de celebração 1600 ms, 1× por chave/execução | `haptica`, `app_theme` |
| `features/dashboard/widgets/hero_geral.dart` | Faixa de KPIs (hoje/semana/total/streak) + barra de meta | `resumoGeralProvider` |
| `features/dashboard/widgets/hero_missao_hoje.dart` | Próximo passo em 1 toque → cronômetro pré-configurado | `sugestaoHojeProvider`, `preSelecaoCronometroProvider` |
| `features/dashboard/widgets/tiles_resumo.dart` | Tiles mês/ano/ontem/média/máximo/ritmo + variação MoM/YoY | `tilesResumoProvider`, comparativos |
| `features/dashboard/widgets/card_diagnostico.dart` | Veredito do dia | `diagnosticoProvider` |
| `features/dashboard/widgets/card_alertas.dart` | Atrasadas por matéria + falso domínio | `alertasProvider` |
| `features/dashboard/widgets/card_prontidao.dart` | % hoje vs projetado, risco, faixa de confiança | `prontidaoProvider` |
| `features/dashboard/widgets/card_edital.dart` | Cobertura + buraco mais caro | `edital_providers` |
| `features/dashboard/widgets/card_caderno_erros.dart` | Vencem hoje + taxa de recuperação | `caderno_providers` |
| `features/dashboard/widgets/card_true_retention.dart` | Retenção real por matéria | `trueRetentionProvider` |
| `features/dashboard/widgets/card_forecast_revisao.dart` | Barras de carga 30 dias | `forecastRevisaoProvider` |
| `features/dashboard/widgets/card_desempenho.dart` | Taxa por matéria (régua Nexus) | `desempenhoPorMateriaProvider` |
| `features/dashboard/widgets/card_rankings.dart` | Mais estudada / melhor dia / ranking de acertos | `rankingsProvider` |
| `features/dashboard/widgets/card_bancas.dart` | Ranking por banca + pior par banca×matéria | `bancas_providers` |
| `features/dashboard/widgets/card_simulados.dart` | Desempenho em simulados (isolado do estudo diário) | `simuladosProvider` |
| `features/dashboard/widgets/card_gamificacao.dart` | Nível/XP/badges + confete de badge nova | `gamificacaoProvider`, `badgesVistasProvider` |
| `features/dashboard/widgets/card_quests.dart` | Checklist do dia | `questsDoDiaProvider` |
| `features/dashboard/widgets/card_plano.dart` | Planejado vs feito (semana/mês/ano) | `planoProvider` |
| `features/dashboard/widgets/card_anos.dart` | Horas por ano + projeção | `anosProvider` |
| `features/dashboard/widgets/card_ambientes.dart` | Participação por ambiente (só visão consolidada) | `ambientesSemanaProvider` |
| `features/dashboard/widgets/card_melhorar_hoje.dart` | Insights acionáveis com atalho de registro | `insightsProvider` |
| `features/dashboard/widgets/heatmap_constancia.dart` | Heatmap calendário + dias congelados | `heatmapDadosProvider`, `CustomPainter` |
| `features/dashboard/widgets/chama_streak.dart` | Chama animada (tremula em risco) | — |
| `features/dashboard/widgets/graficos.dart` | `BarrasSemana`, `LinhaEvolucao`, `DonutDistribuicao` (fallback em barras) | `fl_chart` |
| `features/dashboard/widgets/rotulos_a11y.dart` | Texto por extenso p/ leitor de tela (WCAG 2.2) | `formatters` |
| `features/cronometro/cronometro_controller.dart` | Relógio de parede persistido + `preSelecaoCronometroProvider` | `hive_ce` |
| `features/cronometro/cronometro_screen.dart` | Start/pause/salvar sessão cronometrada | `cronometro_controller`, `registro_form` |
| `features/registro/registro_form.dart` | Formulário de sessão (teoria/prática) | `sessaoEstudoUseCaseProvider` |
| `features/revisoes/revisoes_screen.dart` | Fila pendentes/feitas, concluir com desempenho, adiar | `revisaoUseCaseProvider` |
| `features/materias/materias_screen.dart` | CRUD/menu de matérias | `materiaUseCaseProvider` |
| `features/materias/materia_dialog.dart` | Criação/edição (cor por slot livre) | `materiasProvider` |
| `features/materias/topicos_screen.dart` | Árvore de tópicos + mover/excluir | `topicoUseCaseProvider` |
| `features/materias/importar_edital.dart` | Import de edital colado (dedupe por nome normalizado) | `edital_parser_service` |
| `features/aulas/aulas_screen.dart` | Aulas/PDFs, progresso e ritmo | `aula_service`, `aulaUseCaseProvider` |
| `features/edital/edital_providers.dart` | Linhas/cobertura/distribuição/buracos memoizados | `edital_service` |
| `features/edital/edital_screen.dart` | Edital verticalizado (donut + lista + buracos) | `edital_providers` |
| `features/caderno/caderno_providers.dart` | Fila do dia, resumo, rankings, órfãs | `caderno_erros_service` |
| `features/caderno/caderno_screen.dart` | 3 abas (fila/todas/estatísticas) + foto do enunciado | `image_picker`, `anexosQuestaoRepositorioProvider` |
| `features/caderno/questoes_orfas_screen.dart` | Reatribuição de vínculo órfão | `questoesOrfasProvider` |
| `features/simulados/simulados_screen.dart` | CRUD de simulados/provas manuais | `simuladosProvider` |
| `features/simulados/prova_screen.dart` | Modo prova: setup→execução→correção→resultado | `prova_service`, `execucaoProvaProvider` |
| `features/planejamento/planejamento_screen.dart` | Cronograma semanal + ciclo sugerido + fila de estudo | `planejamento_service` |
| `features/mapa/mapa_estudos_screen.dart` | Árvore matéria→aula→tópico com status/domínio | `mapa_estudos_service` |
| `features/leituras/leituras_screen.dart` | Divisões de PDF + sessões de leitura | `leitura_service` |
| `features/resumos/resumos_screen.dart` | Páginas #SIGLA estilo Obsidian com ligações | `notas_ricas`, `resumosProvider` |
| `features/busca/busca_screen.dart` | Busca global e roteamento por tipo | `busca_service` |
| `features/ambientes/ambientes_screen.dart` | CRUD de ambientes (bloqueia exclusão com matérias) | `ambientesProvider` |
| `features/ambientes/ambiente_selector.dart` | Chip-menu que rescopa o app | `configuracoesProvider` |
| `features/exportar/exportar_screen.dart` | Exports, backup, mesclar/substituir, import `.xlsx` | `export/import/planilha` services, `backupUseCase` |
| `features/configuracoes/configuracoes_screen.dart` | Preferências + wipe out com trava dupla | `apagarDadosUseCaseProvider` |
| `features/onboarding/onboarding_screen.dart` | Tour de 5 passos, uma vez | `configuracoesProvider` |
| `features/mais/mais_screen.dart` | Índice das ferramentas (mobile) | telas |

---

## 3. Mapeamento Detalhado do Código (Função por Função)

### Módulo: `lib/main.dart`

- **`main()`**
  - **Finalidade:** ponto de entrada; instala captura global de erro assíncrono.
  - **Lógica:** `runZonedGuarded(iniciar, handler)`. `ensureInitialized()` e `runApp` devem estar no MESMO zone → ambos dentro de `iniciar`.
  - **Cálculos:** N/A. **E/S:** `void → void`.
- **`iniciar()`**
  - **Finalidade:** sequência de boot re-executável (botão "Tentar de novo").
  - **Lógica:** `passo = armazenamento` → `Hive.initFlutter()` + `HiveBoxes.openAll()` → `passo = migracao` → `migrar()` + `seedResumos()`. Falha ⇒ `runApp(FalhaBootApp(...))` e `return`. Só o bloco de armazenamento é fatal; `_prepararLembreteDiario()` é best-effort.
  - **E/S:** `() → Future<void>`.
- **`_prepararLembreteDiario()`** — reagenda lembrete diário (idempotente) lendo `config` cru do box; qualquer exceção é reportada e engolida.
- **`_instalarCapturaDeErro()`** — `ErrorWidget.builder = construirWidgetDeErro`; `platformDispatcher.onError` retorna `!kDebugMode` (release mantém o app de pé, debug deixa estourar).

### Módulo: `lib/app.dart`

- **`AbaNotifier` / `abaProvider`** — `int` da aba ativa; `ir(aba)` dispara `Haptica.selecao()`. Índices em `Abas` (dashboard 0, cronometro 1, materias 2, revisoes 3, mais 4).
- **`AppEstudos.build`** — `MaterialApp` locale fixo `pt_BR` + 3 delegates de localização; `builder` envolve o `Navigator` em `LuminaBackground`.
- **`_HomeShell.build`** — gate: `!config.onboardingConcluido ⇒ OnboardingScreen`. `IndexedStack` preserva estado das 5 abas. `LayoutBuilder`: `maxWidth ≥ 1080` ⇒ `_Sidebar` + conteúdo; senão `NavigationBar`.
- **`_Sidebar`** — larguras `expandida=240`, `colapsada=72`, limiar de conteúdo `_larguraMeioTermo=(240+72)/2=156`. **Linha crítica:** o conteúdo segue `constraints.maxWidth` (largura REAL animada), não o `bool colapsada` — seguir o bool causava `RenderFlex overflow` durante os 180 ms da animação.

### Módulo: `lib/core/boot/falha_boot.dart`

- **`enum PassoBoot { armazenamento, migracao }`** — cada valor carrega `titulo` + `explicacao` (a reação pedida difere por passo).
- **`FalhaBootApp`** — `MaterialApp` mínimo com cores literais (`#0F1115`, `#171A21`, `#E7E9EE`, `#9BA1AE`, `#FFB4A9`). **Regra de conteúdo:** nunca sugerir "limpar dados do app" (único gesto irreversível disponível ao usuário).
- **`construirWidgetDeErro(FlutterErrorDetails)`** — substitui a caixa cinza do release por bloco legível na subárvore que falhou.

### Módulo: `lib/data/local/hive_boxes.dart`

- **Constantes de box (16):** `ambientes, materias, topicos, aulas, registros, revisoes, config, planejamento, leituras, simulados, resumos, questoes_erradas, anexos_questoes, rollback, cronometro, execucao_prova`.
- **`openAll()`** — `Future.wait` de 16 `openBox`. Todos `Box<Map>` exceto `anexos` = `Box<Uint8List>` (único box binário; Hive serializa `Uint8List` nativamente).
- **`seedResumos()`** — para cada `MateriaCatalogo`: `if (box.containsKey(sigla)) continue;` → idempotente, texto do usuário nunca sobrescrito.
- **`migrar()`**
  - **Lógica:** `versao = config['schemaVersion'].v ?? 0`; se `versao < schemaVersion(=2)` roda passos pendentes (`versao < 1 ⇒ migrarAmbientes()`) e grava `{v: 2}`. Boot em dia = **O(1)**.
  - **Linha crítica:** `repararOrfaos()` roda em **todo** boot (fora do gate de versão) porque Hive não tem transação multi-box.
- **`repararOrfaos()`**
  - **Finalidade:** aula concluída sem NENHUMA revisão associada recebe Revisão 1 retroativa.
  - **Lógica:** monta `Set aulasComRevisao` a partir de `revisoes[].aulaId`; `primeiro = RevisaoService.proximoIntervalo(intervalos, 0)`; para cada aula `concluida ∧ dataConclusao != null ∧ !aulasComRevisao.contains(id)` cria `Revisao(dataAgendada = dataConclusao + primeiro)`. Conservador: só recria quando **zero** revisões referenciam a aula.
  - **Cálculos:** `dataAgendada = DateTime(y, m, d + primeiro)`.
- **`migrarAmbientes()`** — cria ambiente `geral` se box vazio; grava `ambienteId = 'geral'` explícito em matérias antigas (default só em memória deixaria órfãos ao apagar o Geral).

### Módulo: `lib/data/models/*` — invariantes de borda

| Modelo | Invariante aplicada na factory | Fórmula/derivação |
|---|---|---|
| `Materia` | `peso = max(1, peso)`; `intimidade = clamp(1,5)` | `comAtualizacao(t)`, `comExclusao(t)` (tombstone) |
| `Topico` | `peso = max(1, peso)`; `limparParent` desambigua null | `prerequisitos: List<String>` (DAG) |
| `Aula` | `total = max(0,total)`; `lidas = clamp(0, total)` | `progresso = clamp(lidas/total, 0,1)`; `paginasRestantes = clamp(total−lidas, 0, total)` |
| `RegistroHora` | `minutos = clamp(0, 960)`; `questoes = max(0,q)`; `acertos = clamp(0, q)`; página negativa → `null`; `banca = Bancas.normalizar()` | `paginasLidas = manual ?? (fim ≥ ini ? fim−ini+1 : null)`; `paginasPorHora = paginas/(minutos/60)`; `taxaAcerto = acertos/questoes` |
| `Revisao` | — | `statusEm(hoje)`: `feita` → `feita`; `dataAgendada < hoje` → `atrasada`; senão `aFazer` (derivado, nunca gravado) |
| `QuestaoErrada` | `ano ∈ [1990,2100]` senão null; `estabilidade > 0 ∧ finita` senão null; `dificuldade = clamp(1,10)`; datas truncadas no dia | `acertosSeguidos` = run final de `true`; `taxaRefazendo = totalAcertos/tentativas`; `venceEm(hoje) = !arquivada ∧ proximaTentativa ≤ hoje` |
| `ItemProva` | `numero = max(1,n)`; resposta/gabarito `UPPERCASE` sem espaço | alfabeto não é validado (cada banca tem o seu) |
| `ExecucaoProva` | `duracaoMinutos = clamp(1, 960)` | `fimPrevisto = iniciadaEm + duracao`; `ativa = finalizadaEm == null` |
| `ResultadoMateria` | `questoes = max(0,q)`; `acertos = clamp(0,q)` | `erros = q−a`; `taxa = a/q` (null se `q ≤ 0`) |
| `Simulado` | `banca` normalizada no construtor | `taxaGeral = ΣA/ΣQ`; `minutosPorQuestao = tempo/ΣQ` |
| `Leitura` | `partesConcluidas.length` forçado a `partes` | `totalPaginas = fim−ini+1`; `minutosPorPagina` = média ponderada só de sessões com tempo; `minutosParaTerminar = round(restantes × ritmo)` |
| `Configuracoes` | `minutosPadraoRevisao = clamp(0,60)` | defaults: `intervalos=[7,15,30]`, `horaNotificacao=9`, `metaSemanal=1800 min (30h)`, `minutosPadraoRevisao=10` |

- **`Bancas.normalizar(bruta)`** — `trim → sem acento → UPPER → colapsa espaços → _apelidos[x] ?? x`. Vazio ⇒ `null` (nunca string vazia, que poluiria o agrupamento). Apelidos: `CESPE | CESPE/CEBRASPE | CESPE-CEBRASPE | CEBRASPE/CESPE → CEBRASPE`, `FUNDACAO GETULIO VARGAS → FGV`, `FUNDACAO CARLOS CHAGAS → FCC`, `FUNDACAO VUNESP → VUNESP`, `CESGRANRIO FUNDACAO → CESGRANRIO`.
- **`siglaPara(nome)`** (`catalogo_materias.dart`) — remove *stop words* (`de,do,da,dos,das,e,em,no,na,nos,nas,para,ao,à,a,o`); 1 palavra ⇒ 3 primeiras letras; N palavras ⇒ iniciais. Sempre maiúsculo; vazio ⇒ `?`.

### Módulo: `lib/data/repositories/repositorios.dart`

- **`abstract class _HiveRepositorio<T> extends Notifier<List<T>>`**
  - **Finalidade:** repository pattern sobre Hive — box = fonte persistida, `state` = projeção observável.
  - **Contrato de subclasse:** `boxName`, `fromJson`, `toJson`, `idDe`, `comparar`; opcionais `carimbarAtualizacao`, `marcarExclusao`, `estaExcluido`.
  - **`_carregar()`** — `try/catch` **por registro**: item corrompido é `debugPrint` + ignorado, nunca derruba a coleção. Filtra `estaExcluido` (tombstone). Ordena por `comparar`.
  - **`salvar(item)`** — carimba `atualizadoEm = now` se houver `carimbarAtualizacao`; `box.put`; atualiza `state` **incrementalmente** (remove por id + append + sort) — evita `O(box)` por escrita.
  - **`remover(id)`** — sem `marcarExclusao`: `box.delete` (hard). Com: regrava o registro marcado (tombstone) e retira do `state`.
  - **`substituirTudo(itens)`** — `clear()` + `putAll()` + `_carregar()`. **Hard delete, sem tombstone.**
  - **`mesclar(itens)`** — `putAll` sem apagar o resto (import aditivo).
  - **`removerOnde(teste)`** — cascata em lote: um `deleteAll`/`putAll` + uma atualização de `state`.
- **Repositórios concretos:**

| Classe | Box | Ordenação (`comparar`) | Tombstone | Extra |
|---|---|---|---|---|
| `AmbientesRepositorio` | `ambientes` | nome ↑ (lowercase) | não | `proximoCorSlot()` |
| `MateriasRepositorio` | `materias` | nome ↑ | **sim** (`excluidaEm`) | `proximoCorSlot()`, `pesosHistoricos()` |
| `TopicosRepositorio` | `topicos` | nome ↑ | não | `daMateria(id)` |
| `AulasRepositorio` | `aulas` | nome ↑ | não | `daMateria(id)` |
| `RegistrosRepositorio` | `registros` | data ↓ | **sim** (`excluidoEm`) | — |
| `RevisoesRepositorio` | `revisoes` | `dataAgendada` ↑ | não | — |
| `LeiturasRepositorio` | `leituras` | título ↑ | não | — |
| `SimuladosRepositorio` | `simulados` | data ↓ | não | — |
| `ResumosRepositorio` | `resumos` | nome ↑ (id = `sigla`) | não | `salvarTexto()` |
| `QuestoesErradasRepositorio` | `questoes_erradas` | `proximaTentativa` ↑, `criadaEm` ↑ | não | `daMateria`, `ativas` |

- **`MateriasRepositorio.pesosHistoricos()`**
  - **Finalidade:** peso do edital **incluindo matérias excluídas** (tombstone).
  - **Lógica crítica:** lê direto de `_box.values` (não do `state`). Sem isso o XP ponderado degradava minutos de matéria excluída para ×1.0 e **derrubava o XP total** (−9% por matéria peso 5), quebrando a monotonia da gamificação.
- **`proximoCorSlot()`** — primeiro slot `0..7` não usado; se todos usados, `state.length % 8`.
- **`ExecucaoProvaController extends Notifier<ExecucaoProva?>`** — slot único `atual`; `iniciar()` é `await` (a tela só avança com o slot gravado); `atualizar()` é fire-and-forget (state síncrono + `put` sem await); **`mutar(f)`** aplica a mutação sobre o `state` atual, não sobre a cópia capturada na closure da tela (duas edições no mesmo frame não se sobrescrevem); `encerrar()` apaga o slot.
- **`AnexosQuestaoRepositorio`** — **fora** do padrão `_HiveRepositorio`: bytes nunca entram em `state`. `ler(id)`, `salvar(id,bytes)`, `remover(id)` (idempotente), `todos()`, `substituirTudo(map)`, `mesclar(map)`. Chave = id da `QuestaoErrada` (contrato de 1 anexo por questão).

### Módulo: `lib/data/repositories/planejamento_repositorio.dart`

- **`PlanejamentoRepositorio extends Notifier<Map<int,int>>`** — minutos por dia da semana (`1=seg … 7=dom`).
  - **`_chave(ambienteId)`** = `ambienteId == null ? 'semana' : 'semana:$ambienteId'`. Leitura de ambiente sem cronograma próprio **herda** a chave global.
  - **`build()`** — leitura tolerante a dois formatos: novo `{dias:{...}, atualizadoEm}` e legado (mapa direto).
  - **`apagarTudo()`** — `box.clear()`. **Necessário** porque `substituir({})` grava só na chave do ambiente ativo e o fallback de leitura ressuscitaria o cronograma "apagado".

### Módulo: `lib/domain/revisao_service.dart` — **motor FSRS-lite**

Constantes: `_dificuldadeInicial = 5.0` · `_sementeManualDias = 3.0` · `_crescimentoBase = 0.9` · `_freioEstabilidade (w9) = 0.15` · `_taxaReversaoDificuldade = 0.1` · `retencaoAlvoPadrao = 0.9` · `tetoDiasFsrs = 120`.

- **`proximoPassoFsrs({estabilidade, dificuldade, intervaloAtual, diasDeAtraso, taxaAcerto, retencaoAlvo})`**
  - **Finalidade:** passo adaptativo ao concluir uma revisão; retorna `({dias, intervalo, reforco, estabilidade, dificuldade})?`.
  - **Curva base:** `R(t) = 1 / (1 + t/(9·S))` — em `t = S`, `R = 0.9`.
  - **Saneamento:** `S = (S finita ∧ S > 0) ? S : (intervaloAtual > 0 ? intervaloAtual : 3.0)`; `D = clamp(D finita ? D : 5.0, 1, 10)`. *Sem isso, `S ≤ 0` ⇒ `NaN.round()` ⇒ `UnsupportedError` **depois** de a revisão já ter sido salva como feita, matando a cadeia em silêncio.*
  - **Decorrido:** `base = intervaloAtual > 0 ? intervaloAtual : round(S)`; `decorrido = max(1, base + diasDeAtraso)`; `r = 1/(1 + decorrido/(9·S))`; `fracaoDecorrida = clamp(decorrido/base, 0, 1)`.
  - **Régua de desempenho:** `errou ⟺ taxa < 0.75`; `dificil ⟺ 0.75 ≤ taxa < 0.85`; pleno se `taxa ≥ 0.85` **ou** `taxa == null`.
  - **Lapso (`errou`):** `S' = max(1.0, 0.4·S)` ; `D' = rev(D + 1.0)`.
  - **Sucesso:**
    - `bonusEsquecimento = 1 + 2·(1 − r)`
    - `fatorFacilidade = (11 − D)/6` (D=5 ⇒ 1.0)
    - `crescimento = 0.9 · fatorFacilidade · bonusEsquecimento · S^(−0.15) · fracaoDecorrida`
    - se `dificil`: `crescimento ×= 0.5` e `D' = rev(D + 0.5)`; senão `D' = rev(D − 0.3)`
    - `S' = S · (1 + crescimento)`
  - **Reversão à média:** `rev(d) = clamp(d + 0.1·(5 − d), 1, 10)`.
  - **Intervalo:** `fator(R) = 9·(1/R − 1)` (R=0.9 ⇒ 1.0); `dias = round(S' · fator(R))`. Se `!errou ∧ dias > 120` ⇒ **`null`** (cadeia encerra). Senão `dias = clamp(dias, 1, 120)`.
  - **E/S:** `(double?, double?, int, int, double?, double) → ({int dias, int intervalo, bool reforco, double estabilidade, double dificuldade})?`
- **`reagendarPorEstudo(revisoes, topicoId, dataEstudo)`**
  - **Lógica:** para revisões `!feita ∧ topicoId == alvo ∧ intervaloDias > 0`: `nova = dataEstudo + intervaloDias`. **Só empurra:** `if (nova.isBefore(atual)) continue` — sessão retroativa não pode puxar a revisão para o passado e criar atraso fantasma. Retorna só as alteradas.
- **`forecastCarga(revisoes, hoje, {dias = 30})`** — pendentes agregadas por dia; `alvo = max(agendada, hoje)` (atrasadas caem no dia 0); saída densa via `List.generate(dias)` com zeros.
- **`proximoIntervalo(intervalos, atual)`** — menor intervalo configurado `> atual`; `null` encerra. Revisão manual (`atual = 0`) entra no início.
- **`taxaAcertoDe(registros, {materiaId, topicoId, ultimasSessoes = 10})`** — janela de recência: filtra por tópico (ou matéria se `topicoId == null`) com `questoes > 0`, ordena data ↓, soma as 10 primeiras. `taxa = Σacertos/Σquestoes`; `null` se `Σquestoes == 0`.

### Módulo: `lib/domain/dominio_service.dart` — **estimador Elo**

Constantes: `questoesPorPassoCheio = 10` · `ganho = 0.8` · `amostraMinima = 10` · `meiaVidaDias = 60.0`.

- **`dominioDe(candidatos, {referencia})`**
  - **Finalidade:** domínio ∈ [0,1] a partir do histórico de questões; `null` sem sessão com questões.
  - **Algoritmo:** sessões com `questoes > 0` ordenadas por data ↑; `rating = 0` (neutro).
    1. Entre sessões: `rating ×= 0.5^(Δdias/60)` (esquecimento **temporal**, não ordinal).
    2. `observado = clamp(acertos/questoes, 0, 1)` (clamp defensivo contra import adulterado).
    3. `esperado = σ(rating) = 1/(1 + e^(−rating))`.
    4. `peso = min(questoes, 10)/10`.
    5. `rating += 0.8 · peso · (observado − esperado)`.
  - **Staleness final:** se `referencia != null`: `rating ×= 0.5^((referencia − ultimaSessao)/60)`.
  - **Saída:** `(dominio: σ(rating), questoes: Σq, confiavel: Σq ≥ 10)`.
  - **Nota de calibração:** como o domínio passa por sigmoide, o corte 0.75/0.85 no espaço de domínio é **mais estrito** que a mesma taxa de acerto crua.
- **`dominioDoTopico` / `dominioDaMateria`** — açúcar sobre `dominioDe` com filtro por `topicoId`/`materiaId`.
- **`dominioPorMateria(registros, materiaIds, {referencia})`** — agrupa **uma vez** por matéria: `O(registros)` em vez de `O(matérias × registros)`.

### Módulo: `lib/domain/parametros_ciclo.dart`

- **`ParametrosCiclo`** (abstract final) — `blocoMinutos = 15`, `passoPorBloco = 0.02`, `pisoManutencao = 0.08`. **Contrato:** Planejamento e Prontidão **devem** ler daqui — a promessa "seguindo o ciclo você chega no projetado" vale por construção enquanto ambos compartilharem estes valores. `pisoManutencao` só passa a valer quando `(1 − domínio) < 0.08`, i.e. `domínio ≳ 0.92`.

### Módulo: `lib/domain/planejamento_service.dart`

- **`enum DiagnosticoMateria { falsoDominio, teoriaPrioritaria, dominada, regular }`**
- **`diagnostico(intimidade, medido)`**
  - `intimidade ≤ 1` → `teoriaPrioritaria`
  - `medido == null ∨ !medido.confiavel` → `regular` (sem evidência, sem veredito)
  - `intimidade ≥ 4 ∧ dominio < 0.75` → `falsoDominio`
  - `intimidade ≥ 4 ∧ dominio ≥ 0.85` → `dominada`
  - caso contrário → `regular`
- **`dominioInicial(intimidade, medido)`** — `medido.confiavel ? medido.dominio : 0.2 + 0.15·(clamp(intimidade,1,5) − 1)` ⇒ prior mapeia intimidade 1..5 → **0.2 … 0.8**.
- **`distribuirPorUtilidade(minutosTotais, materias, dominios, {bloco=15, passo=0.02, expoente=1.0, pisoManutencao=0})`**
  - **Algoritmo:** mochila gulosa por utilidade marginal decrescente.
  - `deficit_m = (1 − d_m)^expoente`
  - `manutencao_m = pisoManutencao · (1 − recebido_m/minutosTotais)` (decai com o já alocado ⇒ a fatia mínima **roda** entre as dominadas em vez de concentrar na primeira)
  - `utilidade_m = peso_m · max(deficit_m, manutencao_m)`
  - a cada iteração aloca `bloco = min(15, restante)` à maior utilidade; depois `d_m ← min(1, d_m + 0.02·bloco/15)`.
  - **Determinismo:** lista pré-ordenada por `peso ↓, nome ↑` + comparação estrita `>` ⇒ empate resolve pelo peso, depois nome.
  - **Garantia:** `Σ resultado == minutosTotais` exatamente.
- **`cicloPorUtilidade(minutos, materias, registros, {referencia})`** — ponto ÚNICO do ciclo (Planejamento e Sugestão de hoje não podem divergir): `dominioPorMateria` → `dominioInicial` → `distribuirPorUtilidade(pisoManutencao: 0.08)`.
- **`planejadoEntre(cronograma, de, ate)`** — conta ocorrências de cada `weekday` no intervalo: `base = totalDias ~/ 7`, mais 1 para os `totalDias % 7` dias iniciais; `total = Σ minutos_d × ocorrencias_d`.
- **`distribuirPorPeso` / `_distribuir`** — proporcional ao peso com **método do maior resto**: `exato_i = total·p_i/Σp`; `resultado_i = floor(exato_i)`; sobra distribuída 1 a 1 na ordem decrescente de parte fracionária. `Σ` bate exato.
- **`filaDeEstudo({materias, feitoPorMateria, minutosSemanais})`**
  - Só matérias com `minutosAlvo > 0` e não arquivadas; ordem `peso ↓, intimidade ↑, nome ↑`.
  - `restante_i = clamp(alvo_i − feito_i, 0, alvo_i)`; `acumulado += restante_i`; `semanasAteConcluir_i = acumulado/minutosSemanais` (`∞` se `minutosSemanais ≤ 0`). ETA **acumulada** (a semana inteira vai para a matéria da vez).
- **`totalPlanejado(map)`** — soma dos minutos do cronograma.

### Módulo: `lib/domain/prontidao_service.dart`

Constantes: `limiarRisco = 0.75` · `kDispersao = 0.5` (+ `blocoMinutos`/`passoPorBloco` importados de `ParametrosCiclo`).

- **`prontidao(materias, dominios)`** — média ponderada pelo peso do edital: `P = Σ(peso_i · d_i) / Σ peso_i` (só ativas; `d_i` default 0.5; `null` sem matérias ou `Σpeso ≤ 0`).
- **`prontidaoAjustada(materias, dominios)`** — penaliza dispersão (perfil bimodal com pesadas fracas):
  `P_aj = clamp( P − 0.5 · sqrt( Σ peso_i·(d_i − P)² / Σ peso_i ), 0, 1 )`
- **`coberturaConfiavel(materias, medidos)`** — `Σpeso(confiável)/Σpeso ∈ [0,1]`; 0 sem matérias (nunca divide por zero). Responde "quanto da prontidão é evidência e quanto é palpite".
- **`dominiosAtuais(materias, medidos)`** — mapa `id → dominioInicial(intimidade, medido)`.
- **`projetarDominios({materias, dominiosHoje, minutosSemanais, diasAteProva})`**
  - Loop `while (diasRestantes > 0)`: `fracao = min(7, diasRestantes)/7`; `minutosDaSemana = round(minutosSemanais·fracao)`; aloca via `distribuirPorUtilidade(..., pisoManutencao: 0.08)`; para cada matéria `ganho = 0.02·minutos/15` e `d ← min(1, d + ganho)`; `diasRestantes -= 7`.
  - Semana fracionária final recebe minutos proporcionais. Retorna cópia (não muta a entrada).
- **`materiasEmRisco(materias, projetados)`** — ativas com `projetado < 0.75`, piores primeiro.
- **`semMedicao(materias, medidos)`** — ativas sem Elo confiável (chamada de calibração / *cold start*).

### Módulo: `lib/domain/stats_service.dart`

Constantes: `pisoMinutosStreak = 15` · `metaDiasParaCongelamento = 5`.

- **Helpers de data:** `dataSemHora(d)`; `inicioDaSemana(d) = d − (weekday − 1)` (semana começa na segunda).
- **Somatórios:** `minutosNoDia`, `minutosEntre(de, ate)` (intervalo **fechado**), `minutosNaSemana`, `minutosNoMes` (usa `DateTime(y, m+1, 0)` = último dia), `minutosNoAno`.
- **`comparativoMensal(registros, hoje)` / `comparativoAnual`**
  - **Regra:** **parcial-vs-parcial**. O período anterior é cortado no mesmo `hoje.day` (mês) / mesmo mês-dia (ano). Comparar mês corrente incompleto contra mês anterior inteiro sempre mostraria queda falsa.
  - `_fimClampado(primeiroDiaMes, dia)` — descobre o último dia via `DateTime(y, m+1, 0).day` e clampa (evita `31/02` normalizar silenciosamente para março).
  - `variacao = (atual − anterior)/anterior`, **`null` se `anterior == 0`** (fração, não percentual).
- **`minutosPorAno`** — mapa ordenado, só anos com registro.
- **`projecaoAno(registros, hoje)`** — `proj = totalAno + round( (minutos_28d / 28) × diasRestantes )`. Janela fixa de 28 dias corridos; dias sem estudo contam como zero.
- **`minutosPorMateria(registros, {de, ate})`**, **`minutosPorDia`**, **`minutosPorDiaSemana`**, **`serieDiaria(registros, hoje, dias)`** (série densa com zeros), **`resumoDiario`** (média/máx/mín **só sobre dias com registro**).
- **`_diasComEstudoReal(registros)`** — dias cuja soma `≥ 15 min`. Base **anti-gaming**: sessão-token de 1 min não sustenta streak.
- **`streakAtual(registros, hoje)`** — dias consecutivos para trás (sem piso, legado); hoje sem registro não zera (conta a partir de ontem).
- **`_streakCompleto(registros, hoje, metaDiasSemana)`** — motor do streak com **congelamento**:
  - Caminha para trás; dia presente ⇒ `streak++`.
  - Dia ausente ⇒ congelável se `!congeladoNaSemana.contains(semanaDoDia) ∧ diasNaSemana(semanaAnterior) ≥ 5`. Máximo **1 congelamento por semana-calendário**; dia congelado **não** soma em `dias`.
  - Não congelável ⇒ quebra.
  - **Recuperação 24h:** se há um run imediatamente antes do gap, `recuperados = runAnterior ~/ 2` (bônus; o contador exibido recomeça mesmo).
  - `emRisco = streak > 0 ∧ !temHoje`.
- **`streakDetalhado`** → `({dias, congelados, recuperados, emRisco})`; **`diasCongeladosDoStreak`** → `Set<DateTime>` (o heatmap marca o dia protegido).
- **`streakPico(registros)`** — maior run de dias **colados** em todo o histórico.
- **`streakPicoComCongelamento(registros, hoje, {metaDiasSemana = 5})`**
  - **Finalidade:** recorde medido com a MESMA régua do contador exibido. Sem isso, quem descansa 1 dia/semana via a chama em 39 e o pico travado em 6 (badge de 7 dias nunca acendia; XP pagava por 6 para sempre).
  - **Otimização:** só dias que **encerram** um run cru entram como candidatos (dentro de um run, `streak(d+1) = streak(d)+1`) ⇒ custo ≈ `O(runs × tamanho)`.
  - **Monotonia:** acrescentar registros só pode fechar buracos ou torná-los congeláveis — nunca encurta um streak já medido.
- **`desempenhoPorMateria` / `desempenhoPorTopico`** — `{questoes, acertos}` só de registros com `questoes > 0`.
- **`taxaAcertoGeral`** — `Σacertos/Σquestoes`, `null` sem questões.
- **`minutosPorTipo`** — `({teoria, pratica})`.
- **`paginasPorHoraGeral(registros, {materiaId})`** — média **ponderada**: `Σpáginas / (Σminutos/60)`; `null` sem dados.

### Módulo: `lib/domain/retencao_service.dart`

- **`marcadorRevisao = 'Revisão:'`** — contrato com `RevisaoUseCase.concluir`, que grava a sessão de recall com esse prefixo em `tarefa`.
- **`_ehRecall(r)`** = `r.tarefa.startsWith('Revisão:') ∧ (r.questoes ?? 0) > 0`.
- **`geral(registros)`** — `Σacertos/Σquestoes` **só sobre recalls**; `null` sem recall. Interpretação: retenção ≪ alvo ⇒ intervalos longos demais; ≫ alvo ⇒ curtos demais.
- **`porMateria(registros)`** — `Map<materiaId, ({questoes, acertos, taxa})>`; matéria sem recall **não entra** no mapa (o consumidor decide como exibir a ausência).

### Módulo: `lib/domain/gamificacao_service.dart`

Constantes: `xpPorRevisaoFeita = 50` · `xpPorDiaDeStreak = 10` · `maxRevisoesComBonusPorDia = 3`.

- **`multiplicadorPeso(peso)`** = `clamp(1 + 0.1·(peso − 1), 1.0, 1.5)`.
- **`xpTotal(registros)`** = `Σ minutos` (1 XP/minuto, XP base).
- **`xpPonderado(registros, pesoPorMateria)`** = `round( Σ minutos_r × multiplicadorPeso(peso[materia_r] ?? 1) )`.
- **`bonusRevisoes(revisoes)`** — teto **por dia de conclusão**: `Σ_dia min(n_dia, 3) × 50`. Revisões feitas sem `dataConclusao` (dado pré-carimbo) entram num balde próprio **sem teto** — o teto não pode revogar XP já conquistado. *Fecha o loop "criar revisão manual → concluir → +50 XP" infinito.*
- **`xpDetalhado(registros, revisoes, hoje, {pesoPorMateria})`**
  - `base = xpPonderado`; `bonusRevisoes`; `bonusStreak = streakPicoComCongelamento(registros, hoje) × 10`.
  - **Monotonia garantida:** usa o **pico** histórico, não o streak atual ⇒ o XP total nunca cai de um dia para o outro.
  - `total = base + bonusRevisoes + bonusStreak`.
- **`progressoNivel(xp)`** — custo do degrau `n → n+1` é `600·n` XP (10 h no primeiro degrau, crescimento linear):
  ```
  nivel=1; resto=xp; custo=600
  while (resto >= custo) { resto -= custo; nivel++; custo = 600*nivel }
  → (nivel, xpNoNivel: resto, xpParaProximo: custo)
  ```
  XP acumulado para atingir o nível `n`: `Σ(k=1..n−1) 600k = 300·n·(n−1)`.
- **`badges(registros, revisoes, hoje)`** — 8 badges derivadas (nada persistido):

| id | Critério |
|---|---|
| `primeira-sessao` | `registros.isNotEmpty` |
| `dez-sessoes` | `registros.length ≥ 10` |
| `streak-7` | `streakPicoComCongelamento ≥ 7` |
| `streak-30` | `streakPicoComCongelamento ≥ 30` |
| `horas-50` | `Σminutos ≥ 3000` |
| `horas-100` | `Σminutos ≥ 6000` |
| `primeira-revisao` | `revisoes.any(feita)` |
| `revisoes-em-dia` | `revisoes.isNotEmpty ∧ nenhuma atrasada` |

### Módulo: `lib/domain/quests_service.dart`

- **`alvoMaxRevisoes = 3`**. **Decisão de design:** quests **não dão XP** (o bônus dependeria do plano vigente em cada dia passado ⇒ não reproduzível, quebraria a derivação).
- **`questsDoDia({hoje, registros, revisoes, materiaDeficitId, materiaDeficitNome, temTopicos})`**
  1. `estudar-deficit` (ou `estudar-hoje` sem cronograma) — `atual = registrosHoje.any(materiaId == deficit) ? 1 : 0`, alvo 1.
  2. `revisoes-do-dia` — `alvo = clamp(feitasHoje + pendentesAteHoje, 0, 3)`; `atual = clamp(feitasHoje, 0, alvo)`. **Alvo estável:** concluir revisões não encolhe o alvo no meio do dia.
  3. `topico-mapa` (se `temTopicos`) — `atual = registrosHoje.any(topicoId != null) ? 1 : 0`.
- **`QuestDia.concluida`** = `atual ≥ alvo`.

### Módulo: `lib/domain/insights_service.dart`

- **`amostraMinimaQuestoes = 10`** — evita ranking por ruído (`2/2 = 100%`).
- **`maisEstudada(registros)`** — `argmax` de `minutosPorMateria`.
- **`rankingAcertos(registros, {minQuestoes = 10})`** — só matérias com `questoes ≥ 10`; `taxa = a/q`; ordem taxa ↓.
- **`melhorDiaSemana(registros)`** — `argmax` de `minutosPorDiaSemana`.
- **`minutosPorAmbiente(registros, materias, {de, ate})`** — agrega registro→matéria→ambiente; registro de matéria apagada é ignorado.
- **`melhorarHoje({registros, materias, revisoes, hoje})`** — recomendações em ordem de urgência:
  1. revisões atrasadas (`> 0`);
  2. pior matéria do ranking com `taxa < 0.75` (mensagem com % e nº de questões; `materiaId` vira atalho de registro);
  3. `streak.emRisco` (usa `streakDetalhado` — mesma régua da chama — e cita `pisoMinutosStreak`);
  4. fallback `positivo` (a lista **nunca** volta vazia).

### Módulo: `lib/domain/diagnostico_service.dart`

Constantes: `pisoMinutosDia = 15` · `janelaConstancia = 14` · `minutosMinimosParaDiagnostico = 60`.

- **`gerar({...13 parâmetros})` → `Diagnostico`** (`nivel, titulo, mensagem, evidencias, acao`).
  - **Gate:** `totalMinutos < 60` ⇒ `semDados` (nenhum veredito honesto possível).
  - **Votação por pilar** (cada um incrementa `criticos` / `atencoes` / `fortes`):

| Pilar | crítico | atenção | forte |
|---|---|---|---|
| Constância (`diasEstudados14`) | `≤ 5` | `≤ 9` | `> 9` |
| Backlog (`atrasadas`) | `> 5` | `1..5` | `0` |
| Meta semanal (`minutosSemana/metaSemana`) | `< 0.5` | `< 0.9` | `≥ 0.9` |
| True retention | `< 0.75` | `< 0.85` | `≥ 0.85` |
| Acerto geral | `< 0.6` | `< 0.75` | `≥ 0.75` |
| Falso domínio (`> 0`) | — | +1 | — |
| Prontidão ajustada | `< 0.6 ∧ diasAteProva ≤ 45` | `< 0.75 ∧ diasAteProva ≤ 90` | — |

  - **Veredito:** `criticos > 0 → critico`; senão `atencoes > 0 → atencao`; senão `fortes ≥ 3 → forte`; senão `constante`.
  - **`_acao(...)`** — prioridade: zerar atrasadas → estudar matéria de maior déficit → fechar revisões COM questões (se `trueRetention < 0.85`) → sessão de 25 min para proteger streak → manter ritmo.
  - **Determinismo:** mesmos inputs ⇒ mesmo texto. Zero RNG; a variação vem do estado do usuário.
  - **Helpers:** `_pct(v) = '${round(v*100)}%'`; `_horas(min)` → `XhYY` / `Xh` / `Ymin`.

### Módulo: `lib/domain/caderno_erros_service.dart`

- **`fila(questoes, hoje, {pesoPorMateria, limite})`** — questões `venceEm(hoje)`, ordenadas por: **peso do edital ↓** → **atraso ↓** (`proximaTentativa ↑`) → **erros acumulados ↓** (`tentativas − acertos`) → `criadaEm ↑`.
- **`registrarTentativa(questao, acertou, hoje)`**
  - `tentativas' = tentativas + [acertou]`; recalcula `acertosSeguidos`.
  - `intervaloAtual = round(estabilidade) ?? 0`; `diasDeAtraso = hoje − proximaTentativa`.
  - Chama `RevisaoService.proximoPassoFsrs(taxaAcerto: acertou ? 1.0 : 0.0)` — **mesmo motor** das revisões (não duplicar a verdade sobre espaçamento).
  - `dominou = acertosSeguidos ≥ 2 ∨ passo == null` (teto de 120 d = domínio de sobra) ⇒ `arquivada = true`.
  - `proximaTentativa = hoje + (passo?.dias ?? 120)`.
- **`reabrir(questao, hoje)`** — `arquivada = false`, `proximaTentativa = hoje`.
- **`porMateria` / `porTopico` / `porBanca`** — via `_agrupar`: `(total, ativas, dominadas, taxa = Σacertos/Σtentativas)`; chave `null` é ignorada; `taxa = null` se nenhuma tentativa.
- **`ranking(questoes, materias)`** — só matérias com `ativas > 0`; ordem `ativas ↓`, desempate `peso ↓`.
- **`taxaRecuperacao(questoes)`** = `arquivadas/total`; `null` com caderno vazio.
- **`forecast(questoes, hoje, {dias = 14})`** — espelha `RevisaoService.forecastCarga` (atrasadas no dia 0).

### Módulo: `lib/domain/edital_service.dart`

- **`limiarDominio = 0.6`** — **mesmo** limiar de `MapaEstudosService.dominioLiberacao` (duas réguas de "sabe o suficiente" confundiriam o usuário).
- **`enum SituacaoTopico { intocado, estudado, fragil, dominado }`**
- **`linhas(topicos, registros, {referencia})`** — uma passada agrupando registros por tópico; classificação:
  ```
  t.concluido                              → dominado
  minutos == 0 ∧ questoes == 0             → intocado
  medicao == null ∨ !medicao.confiavel     → estudado
  medicao.dominio ≥ 0.6                    → dominado
  senão                                    → fragil
  ```
- **`cobertura(materia, linhasDaMateria)`**
  - `cobertura = Σ peso(dominado) / Σ peso(todos)`; `coberturaTocada = Σ peso(≠ intocado) / Σ peso`.
  - **Regra:** matéria sem tópico ⇒ `cobertura = 0` com `totalTopicos = 0` — **nunca 100%** (edital vazio ≠ edital coberto).
- **`coberturaPorMateria`** — agrupa `linhas` por matéria; só matérias ativas.
- **`coberturaGeral(materias, topicos, registros)`** — ponderação dupla: `peso = pesoMateria × pesoTopico`; `Σpeso(dominado)/Σpeso`. **`null` sem tópico cadastrado** (devolver 0% acusaria um atraso inexistente).
- **`buracos(..., {limite})`** — tópicos `intocado ∨ fragil` de matérias ativas; `prioridade = pesoMateria × pesoTopico`; ordem `prioridade ↓` → `intocado antes de fragil` → `nome ↑`.
- **`distribuicao(...)`** — `Map<SituacaoTopico, int>` (base do donut).

### Módulo: `lib/domain/edital_parser_service.dart`

- **Regex:**
  - `_numerado = ^(\d+(?:\.\d+)*)\s*[\.\)\-–—:]?\s+(.+)$` → nível = nº de pontos na numeração (`1`=0, `1.2`=1, `1.2.3`=2).
  - `_marcador = ^(?:[-•*]|[a-z][\)\.])\s+(.+)$` → nível = `nivelAnterior + 1`.
  - `_numeracaoEmbutida = (?<=[\.;:])\s+(?=\d+(?:\.\d+)*\s*[\.\)\-–—:]?\s+\S)` — quebra o copy/paste de PDF que cola vários itens na mesma linha.
  - `_cabecalhoEmbutido = (?<=[\.;])\s+(?=[A-ZÀ-Ü][A-ZÀ-Ü0-9\s]{2,}:)` — separa cabeçalho de matéria colado no meio da linha.
- **`_fragmentar(texto)`** — split em cascata: `\n` → `;` → `_cabecalhoEmbutido` → `_numeracaoEmbutida`; descarta vazios.
- **`_limparNome(n)`** — remove `[\s\.,;:]+$`.
- **`parse(texto) → List<ItemEdital>`** — classifica cada fragmento (numerado → marcador → texto solto nível 0).
- **`_pareceMateria(f)`** — não numerado, `3 ≤ len ≤ 80`, e (`maiúsculas/letras ≥ 0.7` **ou** termina em `:`).
- **`parseSecoes(texto) → List<SecaoEdital>`** — cabeçalhos abrem seções; itens numerados pertencem à seção corrente; sem cabeçalho, seção única com `materia == null`.

### Módulo: `lib/domain/mapa_estudos_service.dart`

- **`dominioLiberacao = 0.6`**.
- **`statusDe(topico, registros)`** — `concluido` → `emEstudo` (há registro) → `naoIniciado`.
- **`satisfeito(topico, registros)`** = `concluido ∨ (dominio.confiavel ∧ dominio ≥ 0.6)`. **Domínio alto com pouca amostra NÃO libera.**
- **`bloqueadoPor(topico, todos, registros)`** — pré-requisitos não satisfeitos; **id de tópico apagado é ignorado** (nunca trava para sempre).
- **`fronteira(topicos, registros)`** — não concluídos com `bloqueadoPor == []`; ordem `peso ↓`, `nome ↑`.
- **`metricasPorTopico(topicos, registros)`** — uma passada: `O(registros + tópicos·prerequisitos)` (vs `O(tópicos × registros)` por linha). Devolve `MetricasTopico{status, minutos, taxa, dominio, bloqueadoPor}`.
- **`criariaCiclo(topicos, topicoId, prerequisitoId)`** — `true` se auto-referência, ou se `topicoId` é alcançável a partir de `prerequisitoId` (DFS iterativa com `Set visitados`). Garante DAG.

### Módulo: `lib/domain/aula_service.dart`

- **`aplicarSessao(aula, paginasNaSessao, dataSessao)`**
  - `lidas = clamp(aula.paginasLidas + paginas, 0, total)`; `completou = total > 0 ∧ lidas ≥ total`; **`concluiuAgora = completou ∧ !aula.concluida`** ← gatilho único da cadeia de revisões (sessões seguintes não redisparam).
  - `dataConclusao = truncar(dataSessao)` só na transição.
- **`ritmoDaAula(registros, aulaId)`** = `Σpáginas / (Σminutos/60)` sobre sessões `aulaId ∧ tipo == teoria`; `null` sem dados.
- **`minutosParaTerminar(aula, registros)`** = `round(paginasRestantes/ritmo × 60)`; `0` se já terminou; `null` sem ritmo.
- **`minutosPorPagina`** = `60/ritmo`. **`minutosInvestidos`** = `Σ minutos` (teoria).

### Módulo: `lib/domain/leitura_service.dart`

- **`dividir(inicio, fim, partes)`** — blocos contíguos equilibrados: `total = fim−ini+1`; `n = min(partes, total)`; `base = total ~/ n`; `resto = total % n`; as **primeiras `resto` partes** recebem 1 página extra. Diferença máxima entre blocos = 1.
- **`paginasConcluidas(leitura)`** — soma o tamanho dos blocos marcados em `partesConcluidas`.
- **`progresso(leitura)`** = `paginasConcluidas/totalPaginas`.
- **`paginasRestantesDaMateria` / `progressoDaMateria`** — agregação por `materiaId` (`null` sem leituras).
- **`minutosParaTerminar(paginasRestantes, paginasPorHora)`** = `round(restantes/ritmo × 60)`; `null` sem ritmo.

### Módulo: `lib/domain/banca_service.dart`

- **`amostraMinima = 10`**.
- **`agregar(registros, simulados)`** — soma `questoes/acertos` por banca (sessões com `banca != null ∧ questoes > 0`) + simulados (conta `simulados` por banca). **Sem balde "outras"** — misturar estilos mentiria na comparação.
- **`ranking(...)`** — só bancas com `≥ 10` questões; ordem `taxa ↓`, desempate `questoes ↓`.
- **`taxaDaBanca(...)`** = `acertos/questoes`; `null` sem dados.
- **`porBancaEMateria(...)`** — matriz `banca → materia → {questoes, acertos}` (sessões + resultados dos simulados).
- **`pontoFraco(...)`** — pior par `(banca, matéria)` com amostra suficiente; `null` se nenhum atinge o mínimo.
- **`bancasUsadas(...)`** — bancas por frequência de uso ↓, desempate alfabético (alimenta o Autocomplete com o histórico real antes do catálogo).

### Módulo: `lib/domain/prova_service.dart`

- **`materiaNaoClassificada = '_prova_sem_materia_'`** — bucket para questões sem faixa de matéria (prefixo/sufixo `_` não colide com UUID v4).
- **`tempoRestante(execucao, agora)`** = `max(0, fimPrevisto − agora)`; `Duration.zero` após finalizar. **Relógio de parede** — fechar o app não pausa a prova.
- **`progresso(execucao)`** = `(respondidas, total)`.
- **`corrigir(execucao) → CorrecaoProva`**
  - Item **sem gabarito**: fora da apuração (nem acerto, nem erro, nem totais por matéria) — folha incompleta não pode punir.
  - Item **em branco COM gabarito**: conta como **erro**.
  - `embranco` conta toda questão sem resposta (tenha gabarito ou não) — mede o **comportamento** do candidato.
  - Saída: `(acertos, erros, embranco, resultados: List<ResultadoMateria>, itensErrados)`.
- **`_minutosGastos(execucao)`** = `max(0, (finalizadaEm ?? fimPrevisto) − iniciadaEm)` em minutos.
- **`paraSimulado(execucao, correcao, {simuladoId})`** — `tempoMinutos` = **tempo real gasto**, não a duração planejada.
- **`paraQuestoesErradas(execucao, correcao, hoje)`** — 1 `QuestaoErrada` por item errado; **id determinístico `'${execucao.id}-${item.numero}'`** ⇒ recorrigir faz *upsert*, não duplica. Enunciado vazio ⇒ rótulo `'Questão N — <nome da prova>'`.
- **`paraRegistroHora(execucao, correcao, {id})`** — 1 registro `TipoEstudo.pratica`; `materiaId` = a única da correção, ou `materiaNaoClassificada` se 0 ou > 1 (não há como escolher sem inventar peso).

### Módulo: `lib/domain/busca_service.dart`

- **`tamanhoMinimo = 2`** (público — a tela usa a mesma constante) · **`_tamanhoMaximoTermo = 300`** (teto defensivo contra colagem gigante).
- **`_normalizar(t)`** — sem acento (tabela local) + lowercase + espaços colapsados; aplicado **igualmente** ao termo e ao texto do item (senão `orcamentaria` nunca casaria com `Orçamentária`).
- **`_nivel(termo, titulo, corpo)`** — `0` prefixo do título · `1` palavra inteira no título · `2` substring no título · `3` substring no corpo · `null` sem match. **`score = 3 − nivel`** (maior = mais relevante).
- **Segurança:** o split é por regex **fixo** (`_naoAlfanumerico`), nunca compilado a partir do termo digitado ⇒ entrada `.*` é comparação literal, não regex.
- **`buscar(termo, {materias, topicos, questoes, resumos, aulas, simulados})`**
  - **Contrato duro:** envolve tudo em `try/catch` e devolve `const []` em qualquer falha — a busca **nunca** lança (tela que quebra a cada tecla é pior que busca que não acha).
  - Resumo com `texto.trim().isEmpty` é pulado (duplicaria o card da matéria).
  - Ordena `score ↓`, desempate `titulo.toLowerCase() ↑`.
  - `materiaId` só é preenchido para tópico e aula (não têm tela própria — a navegação abre a tela da matéria dona).

### Módulo: `lib/domain/xlsx_reader.dart`

Tetos: `_maxLinhas = 1 048 576` · `_maxColunas = 16 384` · `_maxBytesParteXml = 50 MB` · `_maxBytesArquivo = 64 MB`.

- **`lerAbas(bytes, {maxBytesParte, maxBytesArquivo}) → Map<aba, List<List<String>>>`**
  - Rejeita `bytes.length > 64 MB` **antes** de descomprimir (checagem barata).
  - `ZipDecoder().decodeBytes` em `try/catch` → `FormatException` com texto acionável.
  - Lê `xl/sharedStrings.xml`, `xl/workbook.xml`, `xl/_rels/workbook.xml.rels` e cada worksheet.
- **`_descomprimirLimitado(f, caminho, maxBytes)`** — **defesa contra zip bomb (CWE-400)**.
  - Chama `Inflate.stream(raw, output: _SaidaLimitada)` **diretamente**, não `f.decompress`/`f.content`: o wrapper web (`_zlib_decoder_web.dart`) materializa a parte inteira (`getBytes()`) antes de escrever no output, e o teto agiria tarde demais. `Inflate` (Dart puro) escreve bloco a bloco ⇒ corte **antes** da materialização, inclusive no alvo web.
  - `CompressionType.none` ⇒ copia com teto; `deflate` ⇒ inflação incremental; outro método ⇒ `FormatException` explícita (OOXML só usa deflate/stored).
  - Teto medido sobre **bytes reais**, nunca sobre o `size` do header (que o atacante controla).
- **`_SaidaLimitada extends OutputMemoryStream`** — sobrescreve `writeByte`/`writeBytes`/`writeStream` lançando `_LimiteExcedido` ao passar do teto.
- **`_mapearAbas`** — resolve `r:id → Target` pelo `.rels`; fallback `worksheets/sheet<N>.xml`.
- **`_lerPlanilha`** — preserva a numeração original das linhas (`r`), preenchendo as puladas com `const []`; valida limites de linha/coluna.
- **`_valorDe(c, compartilhadas)`** — `inlineStr` → concatena `<t>`; `t="s"` → índice em sharedStrings (com bounds check); `t="b"` → `'true'/'false'`; senão valor cru. **Datas saem como serial do Excel** (a conversão é do serviço de import, que sabe quais colunas são datas).
- **`_colunaDe('B3')`** — base-26 sobre `A..Z` → índice 0-based (`B` → 1).

### Módulo: `lib/domain/export_service.dart`

- **`csvRegistros(registros, materias, topicos)`** — convenção **Excel pt-BR**: separador `;`, decimal com vírgula, data `dd/MM/yyyy`, `\r\n`.
- **`csvBi(registros, materias, topicos, {metaSemanalMinutos})`** — convenção **BI**: separador `,`, decimal com **ponto**, datas **ISO** `yyyy-MM-dd`, colunas `snake_case`, 1 linha por sessão. `horas = minutos/60` com 4 casas.
- **`modeloEstrela({registros, materias, topicos, ambientes})` → `Map<arquivo, csv>`**
  - `fato_registros.csv` — grão sessão: chaves + medidas (`erros = questoes − acertos`).
  - `dim_materia.csv`, `dim_topico.csv`, `dim_ambiente.csv`, `dim_data.csv`.
  - **Integridade referencial:** chave presente no fato e ausente na dimensão (matéria/tópico excluído com histórico preservado) recebe **linha sintética** (`nomeMateriaExcluida = '(matéria excluída)'`, `nomeTopicoExcluido = '(tópico excluído)'`), evitando relacionamento quebrado no Power BI.
  - `dim_data` cobre do primeiro ao último registro com `ano, mes, nome_mes, dia, dia_semana, nome_dia_semana, semana_inicio, trimestre = (mes−1)~/3 + 1, eh_fim_de_semana = weekday ≥ 6` — relacionamento 1:* pronto, sem `CALENDARAUTO`.
- **`zipModeloEstrela(tabelas)`** — `ZipEncoder` sobre `utf8.encode` de cada CSV.
- **`_semFormula(valor)`** — **defesa contra CSV injection (CWE-1236)**: valor iniciado em `= + - @ \t \r` recebe apóstrofo prefixado. O Excel executa essas células **mesmo entre aspas**.
- **`_campo` / `_campoBi`** — quoting (`;`/`,`, aspas, quebra de linha) com escape `"` → `""`.
- **`jsonCompleto({...})`** — dump `versao: 1` com `exportadoEm`, todas as coleções, `planejamento` (chaves stringificadas), `anexos` (**base64**, +33% de tamanho), `configuracoes` e `escopo` opcional. Campos tolerantes: `ambientes`, `resumos`, `questoesErradas`, `anexos`, `configuracoes`.
- **`jsonAmbiente({ambiente, ...})`** — backup **PARCIAL** marcado com `escopo: 'ambiente'`: só o ambiente, suas matérias e o que pende delas (+ simulados e questões do escopo, com **filtro de anexos por questão**). Leituras/resumos/planejamento ficam de fora (são globais; `Resumo` não tem `ambienteId`).

### Módulo: `lib/domain/import_service.dart`

- **`parseBackup(jsonTexto) → BackupImportado`**
  - `jsonDecode` → exige `Map` → exige `versao == 1`, senão `FormatException` explícita.
  - `lista<T>(chave, fromJson)` — chave ausente ⇒ `[]` (retrocompatível); não-lista ou item inválido ⇒ `FormatException` com contexto.
  - `planejamento` — só dias `1..7`; valor não numérico ⇒ `FormatException` (um `as num` lançaria `TypeError` e **furaria o catch da UI**); minutos negativos ⇒ 0.
  - `anexos` — valor não-`String` ⇒ `FormatException`; `base64Decode` já lança `FormatException` nativa para texto corrompido.
  - **Nunca importa parcial em silêncio.**
- **`BackupImportado.parcial`** = `escopo != null` — a UI só pode **mesclar** um backup parcial.
- **`ambientesOuGeral(agora)`** — backup pré-Ambientes recebe o ambiente `geral`.

### Módulo: `lib/domain/planilha_import_service.dart`

- **`parse(abas, {materiasExistentes}) → PlanilhaImportada`**
  - Detecta o papel de cada aba pelo cabeçalho: **registro** (`data` + `horas|minutos|tempo`), **revisão** (`data` + `intervalo`, ou nome da aba contém `revis`), **pesos** (sem `data` + `peso`). Máximo 1 aba por papel.
  - Nenhuma aba reconhecida ⇒ `FormatException` com o contrato esperado.
  - **IDs determinísticos:** `xlsx-materia-<chave>`, `xlsx-topico-<materiaId>-<chave>`, `xlsx-registro-<linha>-<yyyy-MM-dd>`, `xlsx-revisao-<linha>-<yyyy-MM-dd>` ⇒ re-importar **sobrescreve**, não duplica.
  - **Aditivo:** matérias novas e atualizadas voltam separadas; a UI mescla.
- **`_acharCabecalho(linhas)`** — varre as 10 primeiras linhas atrás de `materia` + (`data` ∨ `peso`).
- **`_chaveColuna(texto)`** — mapeia rótulo → chave canônica. **Armadilhas tratadas:** `Páginas/hora` (derivada) retorna `null` antes de cair em `horas`; `minimo` não cai em `minutos`.
- **`_lerRegistros(...)`** — trata **"Tempo" mesclado** sobre subcolunas: se a linha seguinte ao cabeçalho traz `Horas`/`Minutos` (ou `h`/`min`) sob a célula `Tempo`, remapeia e avança `inicioDados`. `totalMinutos = round(horas×60 + minutos)` ou `_parseTempoMinutos(tempo)`. Linha sem data/matéria/tempo ⇒ **aviso** (nunca descarte silencioso).
- **`_lerRevisoes(...)`** — `feita` se status ∈ `{feita, concluida, ok, sim}`; título default `'Revisão de <matéria>'`.
- **`_lerPesos(...)`** — `peso = max(1, peso)`; lê `questoes` e `minimo`.
- **`_acharMetaSemanal(abas)`** — procura rótulo contendo `planejad` **e** `semana`; valor = primeira célula numérica à direita (ou logo abaixo); aceita `0 < v ≤ 168` ⇒ `round(v × 60)` minutos.
- **`_parseData(texto)`** — 3 formatos:
  1. **Serial Excel** (`20000 ≤ s ≤ 80000`): `DateTime(1899,12,30) + floor(s) dias` — a epoch 1899-12-30 absorve o bug do ano bissexto de 1900.
  2. `dd/MM/yyyy` (ano < 100 ⇒ `+2000`), validado em `[2000, 2100]`.
  3. ISO-8601, mesma validação de ano.
- **`_parseTempoMinutos(texto)`** — ordem de convenções: `h:mm[:ss]` → `h*60+m`; `v < 1` ⇒ fração de dia (`v*24*60`); `1 ≤ v ≤ 24` ⇒ horas decimais (`v*60`); `v > 24` ⇒ já são minutos.
- **`_parseNumero(texto)`** — aceita `1.5`, `1,5` e `1.234,5` (pt-BR com milhar).

### Módulo: `lib/application/sessao_estudo_use_case.dart`

- **`registrar(registro) → ResultadoSessao`**
  1. `registrosProvider.salvar(registro)`.
  2. **Aula:** só `TipoEstudo.teoria` conta páginas (`paginas = tipo == teoria ? paginasLidas ?? 0 : 0`). Se há aula e `paginas > 0` → `AulaService.aplicarSessao` → salva aula → se `concluiuAgora` chama `criarCadeiaParaAula`.
  3. **Reancoragem:** se `topicoId != null` → `RevisaoService.reagendarPorEstudo` → **`mesclar` em lote** (N revisões = 1 escrita) → `NotificacoesRevisao.sincronizar` para cada.
  - **Saída:** `(aulaAtualizada, aulaConcluiuAgora, primeiraRevisao, revisoesReancoradas)` — a UI decide o texto.
- **`criarCadeiaParaAula(aula, materiaNome)`**
  - `primeiro = proximoIntervalo(config.intervalosRevisao, 0)`; `null` ⇒ não cria.
  - **Dedupe:** se já existe revisão **pendente** com aquele `aulaId`, retorna `null` (uma cadeia por aula).
  - `dataAgendada = aula.dataConclusao + primeiro`; título `'<matéria> — <aula> (<primeiro>d)'`.

### Módulo: `lib/application/revisao_use_case.dart`

- **`concluir(revisao, {questoes, acertos, minutos}) → ResultadoConclusao`**
  1. `minutosDaSessao = minutos ?? config.minutosPadraoRevisao` (default 10; `0` volta ao comportamento antigo). *Sessão de 0 min zerava o "mínimo diário" e inflava a contagem de sessões.*
  2. Se `questoes > 0 ∧ acertos != null`: grava `RegistroHora(tipo: pratica, tarefa: 'Revisão: <titulo>')` — **canal único** de acerto, que alimenta o Elo **e** o `RetencaoService`.
  3. Salva `revisao.copyWith(feita: true, dataConclusao: agora)` + sincroniza notificação.
  4. **Sinal do FSRS:** `taxa = taxaDaRevisao ?? taxaJanela`. `taxaDaRevisao = clamp(acertos,0,questoes)/questoes` é **primária**; a janela das últimas 10 sessões é só *fallback*. *A janela diluía um 0/10 de recall entre sessões boas de outros tópicos — pior nas cadeias de aula, que não têm `topicoId`.*
  5. `diasDeAtraso = truncar(agora) − truncar(dataAgendada)` — diferença entre **dias de calendário**; `inDays` sobre instantes truncava em direção a zero e enfraquecia o freio de antecipação em 1 dia.
  6. `proximoPassoFsrs(...)`; `null` ⇒ cadeia encerrada.
  7. Cria a sucessora: `titulo = base + (reforco ? ' (reforço)' : ' (<dias>d)')` (regex `' \((\d+d|reforço)\)$'` remove o sufixo anterior); herda `topicoId` **e `aulaId`** (linhagem — sem isso o dedupe de `criarCadeiaParaAula` perderia as sucessoras); carrega `estabilidade`/`dificuldade` novos.
- **`adiar(revisao, dias)`** — `dataAgendada += dias` + re-sincroniza notificação.
- **`criarManual({materiaId, titulo, data})`** — `intervaloDias = 0` (entra no início da cadeia).

### Módulo: `lib/application/notificacoes_revisao.dart`

- **`sincronizar(revisao, hora)`** — ponto único: `cancelar(id)` sempre; `agendarRevisao(...)` só se `!revisao.feita`. Antes essa dupla estava copiada em 4 fluxos.

### Módulo: `lib/application/materia_use_case.dart` · `topico_use_case.dart` · `aula_use_case.dart`

Regra comum (doc-store **sem FK** ⇒ integridade referencial é da aplicação):

| Caso de uso | Remove | Preserva (e por quê) |
|---|---|---|
| `MateriaUseCase.excluirEmCascata(materiaId)` | revisões **pendentes** (+ cancela lembrete), tópicos, aulas, a matéria (tombstone) | `RegistroHora` (log histórico prometido na UI); revisões **feitas** (contam XP — apagar rebaixaria nível) |
| `TopicoUseCase.excluirEmCascata(topicoId)` | revisões pendentes do tópico (+ lembrete), o tópico | registros (o `topicoId` pendurado é inerte — todo consumidor filtra por id existente); revisões feitas |
| `AulaUseCase.excluirEmCascata(aulaId)` | revisões pendentes da cadeia (+ lembrete), a aula | registros — só o vínculo é limpo via `RegistroHora.semAula(agora)` |

- **`TopicoUseCase.excluirEmCascata` — religação da árvore:** subtópicos diretos **sobem para o pai do excluído** (`limparParent` quando o excluído era raiz — senão `parentId: null` cairia no `??`); arestas `prerequisitos` que citavam o tópico são removidas.
- **`TopicoUseCase.podeMoverPara(topicos, topicoId, novoPaiId)`** — **estática e pura** (testável sem Flutter). `novoPaiId == null` ⇒ sempre `true`. Bloqueia: mover para si mesmo; mover para **descendente** (sobe a ascendência do destino com `Set visitados` que blinda contra ciclo já existente na massa importada); mover para tópico de **outra matéria**.
- **`TopicoUseCase.excluirTodosDaMateria(materiaId)`** — passa pela mesma cascata, item a item.

### Módulo: `lib/application/backup_use_case.dart`

- **Problema resolvido:** `substituirTudo` escreve em ~11 boxes em sequência e o Hive **não tem transação entre boxes**.
- **`snapshotAtual()`** — `ExportService.jsonCompleto` de tudo que está gravado agora (inclui anexos e configurações) — mesmo formato do backup manual, então o snapshot também serve como arquivo de recuperação.
- **`restaurarSubstituindo(backup)`**
  - `backup.parcial ⇒ StateError` (recusa também aqui, não só na tela).
  - Grava snapshot no box `rollback` (slot `ultimo`) → `_aplicarSubstituindo(backup)` → em qualquer exceção, reaplica o snapshot (best-effort, com `try/catch` próprio) e **repropaga o erro**.
- **`desfazerUltimaRestauracao()`** — reaplica o snapshot e o consome; `false` se não há nada a desfazer.
- **`_aplicarSubstituindo(backup)`** — ordem **filhos→pais**; limpa `ambienteAtivoId` (pode não existir no backup); preferências só são tocadas se o arquivo as traz (backup antigo não pode zerar a meta semanal); `NotificacoesService.cancelarTodas()` ao final (as revisões restauradas têm ids novos ⇒ lembretes antigos ficariam órfãos no SO).

### Módulo: `lib/application/apagar_dados_use_case.dart`

- **`contarRegistrosParaApagar() → ContagemDados`** — leitura **síncrona** dos `state` (sem tocar o Hive) para o diálogo de confirmação.
- **`apagarTudo()`** — `substituirTudo([])` (= `box.clear()`, **hard delete sem tombstone**) na ordem filhos→pais; inclui: anexos (`substituirTudo({})` — senão fotos ficam órfãs), boxes de slot único `execucao_prova` e `cronometro` (`Hive.box(...).clear()`), `planejamentoProvider.apagarTudo()` (**não** `substituir({})`, que é escopado por ambiente), limpeza do `ambienteAtivoId` e `NotificacoesService.cancelarTodas()`.

### Módulo: `lib/features/dashboard/dashboard_providers.dart`

- **`agoraProvider : Provider<DateTime Function()>`** — instante injetável. Existe só para congelar o cronômetro regressivo da prova em golden test (`overrideWithValue(() => instanteFixo)`). **Só o RENDER usa**; callbacks de ação usam `DateTime.now()` direto.
- **`hojeProvider : Provider<DateTime>`** — data truncada, identidade estável entre rebuilds (base da memoização). **Agenda `Timer` para a próxima meia-noite e chama `ref.invalidateSelf`**, cancelado em `onDispose`. *Sem isso, app aberto às 23:59 ficava preso no dia anterior (streak/quests/"Hoje" mentindo).*
- **Agregados** (todos `Provider` memoizados; recomputam só quando uma dependência muda por `==`):

| Provider | Saída | Regra-chave |
|---|---|---|
| `resumoGeralProvider` | `ResumoGeral` | `metaSemana = totalPlanejado(plano) > 0 ? cronograma : config.metaSemanalMinutos`; `progressoMeta = clamp(feito/meta, 0, 1)` (alimenta `LinearProgressIndicator`, que lança fora de [0,1]); `progressoMetaReal` **sem teto** para exibir 186% |
| `desempenhoPorMateriaProvider` | `Map<id,{q,a}>` | compartilhado por 3 cards |
| `dominioPorMateriaProvider` | `Map<id, MedicaoDominio?>` | uma passada Elo com `referencia: hoje` (staleness) |
| `taxaAcertoGeralProvider` | `double?` | — |
| `trueRetentionProvider` | `(geral, porMateria)` | — |
| `forecastRevisaoProvider` | 30 dias | — |
| `rankingsProvider` | mais estudada / ranking / melhor dia | — |
| `insightsProvider` | `List<InsightAcao>` | — |
| `alertasProvider` | atrasadas por matéria + falso domínio | falso domínio pela **mesma** medição Elo do ciclo |
| `sugestaoHojeProvider` | `(materia, deficitMinutos, proximoTopico)` | `deficit = alvoDoCiclo − feitoNaSemana`; `argmax`; tópico vem de `MapaEstudosService.fronteira` |
| `planoProvider` | semana/mês/ano planejado×feito | sem cronograma: `planejado = round(metaSemanal × dias/7)` |
| `tilesResumoProvider` | mês/ano/ontem/média/máx/ritmo | — |
| `comparativoMensalProvider` / `comparativoAnualProvider` | `Comparativo` | parcial-vs-parcial |
| `anosProvider` | por ano + total + projeção | — |
| `prontidaoProvider` | `ProntidaoResumo?` | agregação mais cara; `null` sem ambiente com `dataProva` ou sem matérias; `ajustada` cai em `prontidaoProva` se `null` |
| `barrasSemanaProvider` / `serieEvolucaoProvider` (14 d) / `donutProvider` | dados de gráfico | ordenados por minutos ↓ |
| `gamificacaoProvider` | xp/nível/badges | **SEMPRE global** (trocar de ambiente não rebaixa nível); usa `pesosHistoricos()` |
| `badgesVistasProvider` | `Set<String>?` | `null` = não inicializado; base da celebração de badge **nova** |
| `questsDoDiaProvider` | `List<QuestDia>` | escopo do ambiente |
| `heatmapDadosProvider` | minutos/dia + dias congelados | — |
| `diagnosticoProvider` | `Diagnostico` | **só composição** de providers memoizados (nenhuma passada extra); `diasEstudados14 = serie.where(minutos ≥ 15).length` |
| `ambientesSemanaProvider` | por ambiente | só na visão consolidada |

### Módulo: `lib/features/caderno/caderno_providers.dart`

- **`questoesErradasDoAmbienteProvider`** — escopo por associação via `materiaId` (`QuestaoErrada` não carrega `ambienteId`).
- **`_pesoPorMateriaCadernoProvider`** — `{id: peso}` das matérias vivas (matéria fora do mapa cai no peso 1, default do serviço).
- **`filaDoDiaProvider`**, **`resumoCadernoProvider`** (`totalAtivas`, `totalDominadas`, `venceHoje`, `taxaRecuperacao`), **`rankingCadernoProvider`**, **`forecastCadernoProvider`** (14 d).
- **`ordenarPorBanca(questoes)` / `ordenarPorTopico(questoes, topicos)`** — **funções puras** (testáveis sem `ref`); ordem `ativas ↓`, `total ↓`, chave ↑. `ordenarPorTopico` só inclui tópicos que ainda existem.
- **`bancasDoCadernoProvider`** — **não** escopado por ambiente (banca é classificação estável).
- **`calcularQuestoesOrfas(questoes, materias, topicos)`** — pura; `materiaInexistente` tem precedência sobre `topicoInexistente`.
- **`questoesOrfasProvider`** — varre as coleções **globais** (questão órfã não pertence a ambiente nenhum; filtrar pelo ativo esconderia o aviso).

### Módulo: `lib/features/cronometro/cronometro_controller.dart`

- **`CronometroState.restaurar(raw)`** — sessão que estava rodando volta **PAUSADA** no último tempo salvo: não perde o estudo nem conta o tempo com o app fechado.
- **`CronometroController`** — relógio de parede: `_acumulado` (segmentos fechados) + `_inicioSegmento`; `_decorrido = _inicioSegmento == null ? _acumulado : _acumulado + (now − _inicioSegmento)`.
  - `iniciar/pausar/retomar/descartar`; `_ligarTick()` = `Timer.periodic(500 ms)`.
  - **`_persistir`** — grava no máximo **1×/segundo** enquanto roda (`_ultimoSegundoSalvo`), sempre ao pausar. Payload `{elapsedMs, rodando}`.
- **`preSelecaoCronometroProvider`** — payload one-shot do deep link "Estudar agora" (`definir` → tela consome → `consumir`).

### Módulo: `lib/features/edital/edital_providers.dart`

- **`limiteBuracosEdital = 10`** — número único para a tela e o card (senão discordariam sobre prioridade).
- `_topicosDoAmbienteProvider` → `linhasEditalProvider` (base memoizada) → `linhasPorMateriaEditalProvider`, `coberturaPorMateriaEditalProvider`, `coberturaGeralEditalProvider`, `distribuicaoEditalProvider`, `buracosEditalProvider`. Todos passam `referencia: hoje` (nunca `DateTime.now()`).

### Módulo: `lib/features/dashboard/bancas_providers.dart`

- `_simuladosDoAmbienteProvider`, `bancasUsadasProvider` (lista vazia ⇒ `CardBancas` se esconde), `rankingBancasProvider`, `pontoFracoBancaProvider`. **Nenhum usa `hojeProvider`** — `BancaService` não olha data.

### Módulo: `lib/features/simulados/prova_screen.dart`

- **`enum _Fase { setup, execucao, correcao, resultado }`** — a transição é decisão **LOCAL** do widget, não reativa ao provider: após "Corrigir e salvar" a execução é apagada do Hive (`encerrar()`), e uma fase derivada do provider jogaria a tela de volta ao setup exatamente quando deveria mostrar o resultado.
- **`initState`** — retoma pela persistência: `ativa == null ⇒ setup`; `ativa.ativa ⇒ execucao`; senão `correcao`.
- **`_ProvaSetup`** — `_FaixaMateria` (faixa `1-20 → materiaId`) vira `materiaId` de cada `ItemProva` gerado.
- **`_ProvaExecucao`** — o cronômetro regressivo lê `agoraProvider` para render, mas o tempo **sempre** vem de `ProvaService.tempoRestante`.
- **`_corrigirESalvar(execucao)`** — `corrigir` → `paraSimulado` (mesmo id) → `paraQuestoesErradas` (upsert determinístico) → `paraRegistroHora` → `encerrar()`.

### Módulo: `lib/features/registro/registro_form.dart`

- **`_salvar()`** — valida `minutos > 0`; monta `RegistroHora` com `data = dia escolhido + hora atual`; **campos por tipo:** teoria ⇒ `topicoId/questoes/acertos/banca = null` e `paginasLidasManual = _paginasLidas`; prática ⇒ o inverso. Toda a orquestração fica em `SessaoEstudoUseCase.registrar`; a tela só formata o retorno (aviso de aula/revisão) e escolhe a háptica (`celebrar` se concluiu aula, senão `leve`).
- **`opcoesBanca`** — histórico do usuário primeiro, catálogo depois, sem duplicar (`Set.add` descarta a 2ª ocorrência preservando a ordem).

### Módulo: `lib/features/caderno/caderno_screen.dart`

- 3 abas: **fila** (refazer com resposta escondida), **todas** (filtros `ativas|dominadas|todas`), **estatísticas**.
- **`_selecionarFoto(source)`** — `ImagePicker().pickImage(maxWidth: 1600, imageQuality: 70)` — compressão obrigatória na captura porque o backup JSON carrega os bytes em base64 (+33%).
- **Contrato dos anexos:** a UI decide o ícone **só pela flag** `temAnexo` (nunca lendo o box); `_salvar()` reconcilia flag ↔ box (`salvar`/`remover`) usando o **mesmo id** da questão; exclusão de questão remove o anexo em cascata.

### Módulo: `lib/features/exportar/exportar_screen.dart`

- **Exports:** CSV pt-BR · CSV BI · `modelo_estrela.zip` · JSON completo · JSON de ambiente.
- **`_importarPlanilha`** — `file_selector` → `XlsxReader.lerAbas` → `PlanilhaImportService.parse` → **`mesclar`** (aditivo) em matérias/tópicos/registros/revisões.
- **`_importarMesclando`** — `ImportService.parseBackup` → `mesclar` em todas as coleções + anexos. Nada é apagado.
- **`_importarBackup` (substituir)** — bloqueia backup `parcial` com instrução explícita ("Use Importar e mesclar"); chama `backupUseCase.restaurarSubstituindo` e oferece **Desfazer** (`desfazerUltimaRestauracao`).

### Módulo: `lib/features/*` — demais telas (regra própria)

| Tela | Regra não derivável do domínio |
|---|---|
| `dashboard_screen.dart` | Frase do dia = `frasesDoDia[diaDoAno − 1]` (366 itens, determinístico); estado vazio ensina os 2 caminhos de entrada |
| `revisoes_screen.dart` | Dualidade Pendentes/Feitas; concluir abre captura de `questoes/acertos/minutos` |
| `materias_screen.dart` / `materia_dialog.dart` | Cor = próximo slot livre da paleta e **nunca muda** (cor segue a entidade) |
| `topicos_screen.dart` | Renderização `_emOrdemHierarquica` resistente a ciclo em `parentId` |
| `importar_edital.dart` | Dedupe por nome normalizado sob o mesmo pai ⇒ re-importar só adiciona o que faltou |
| `mapa_estudos_screen.dart` | Árvore matéria→aula→tópico com `MetricasTopico` pré-computadas |
| `planejamento_screen.dart` | Cronograma por dia da semana + ciclo sugerido + fila de estudo (ETA) |
| `leituras_screen.dart` | Data padrão = hoje mas editável; min/pág e projeção são calculados, nunca digitados |
| `resumos_screen.dart` | Páginas visíveis = catálogo + matérias sem página; sigla derivada com sufixo numérico em colisão; página só é gravada ao salvar texto; `#TAG` vira ligação |
| `simulados_screen.dart` | Totais/taxa/min-questão derivados; nunca inputados |
| `ambientes_screen.dart` | **Ambiente com matérias não pode ser excluído** |
| `busca_screen.dart` | `< tamanhoMinimo` mostra dica em vez de lista; roteamento por tipo; `null` se a matéria referenciada sumiu |
| `configuracoes_screen.dart` | Wipe out com **trava dupla**: contagem exata + digitar `APAGAR` |
| `onboarding_screen.dart` | 5 passos, uma única vez; "Pular"/"Começar" gravam `onboardingConcluido` |
| `graficos.dart` | `maxFatiasDonut = 5` ⇒ acima disso troca rosca por barras horizontais; `≥ 6000 min (100h)` usa formato compacto no miolo |
| `heatmap_constancia.dart` | Nível por minutos: `0` · `<30 →1` · `<60 →2` · `<120 →3` · `≥120 →4`; tom **sequencial** (safira, alpha 0.28/0.50/0.75/1.0); dia congelado = contorno na cor da chama |
| `confete_leve.dart` | 1600 ms; 1 celebração por `chave` por execução |
| `chama_streak.dart` | Pulso de 900 ms só quando `emRisco` |
| `rotulos_a11y.dart` | Rótulo semântico por extenso ("1 hora e 35 minutos") — leitor de tela não reconhece "1h 35min" |

---

## 4. Regras de Negócio e Estado

### 4.1 Estados globais / providers-raiz

| Estado | Provider / chave | Propósito |
|---|---|---|
| Aba ativa | `abaProvider` (`int`) | Navegação; permite deep link do dashboard |
| Ambiente ativo | `configuracoes.ambienteAtivoId` → `ambienteAtivoProvider` | **Rescopa o app inteiro**; `null` = visão consolidada; ambiente inexistente cai na consolidada (nunca tela vazia sem explicação) |
| Data corrente | `hojeProvider` | Base estável de toda a matemática de datas; auto-invalida à meia-noite |
| Instante | `agoraProvider` | Só render; injetável para golden test |
| Preferências | box `config`, chave `config` | Intervalos, metas, lembretes, onboarding, sidebar |
| Cronograma | box `planejamento`, chave `semana` \| `semana:<ambienteId>` | Minutos por dia da semana; leitura escopada com fallback global |
| Cronômetro | box `cronometro`, chave `atual` | `{elapsedMs, rodando}`; sobrevive a F5/kill |
| Prova em curso | box `execucao_prova`, chave `atual` | Slot **único**; iniciar outra substitui |
| Snapshot de rollback | box `rollback`, chave `ultimo` | `{json, criadoEm}`; habilita "Desfazer" |
| Versão de schema | box `config`, chave `schemaVersion` | `{v: 2}` |
| Badges vistas | `badgesVistasProvider` (memória) | Celebra só conquista **nova** |
| Pré-seleção do cronômetro | `preSelecaoCronometroProvider` (memória) | Payload one-shot do "Estudar agora" |

### 4.2 Réguas numéricas do produto (fonte única)

| Régua | Valor | Onde |
|---|---|---|
| Status de desempenho (Nexus) | `<0.75` crítico · `0.75–0.84` atenção · `≥0.85` bom | `StatusColors.porTaxa`, FSRS, diagnóstico |
| Amostra mínima de questões | `10` | `DominioService`, `InsightsService`, `BancaService` |
| Domínio que libera pré-requisito / conta como dominado | `0.6` (com amostra confiável) | `MapaEstudosService`, `EditalService` |
| Piso de minutos para o dia contar | `15` | `StatsService.pisoMinutosStreak`, `DiagnosticoService.pisoMinutosDia` |
| Congelamento de streak | 1/semana, exige `≥5` dias na semana anterior | `StatsService` |
| Teto de intervalo FSRS | `120` dias | `RevisaoService.tetoDiasFsrs` |
| Retenção-alvo | `0.9` | `RevisaoService.retencaoAlvoPadrao` |
| Meia-vida do Elo | `60` dias | `DominioService.meiaVidaDias` |
| Bloco do ciclo / passo de domínio / piso de manutenção | `15 min` / `+0.02` / `0.08` | `ParametrosCiclo` |
| Limiar de risco na prontidão / peso da dispersão | `0.75` / `0.5σ` | `ProntidaoService` |
| Teto de sessão / prova | `960 min (16h)` | `RegistroHora`, `ExecucaoProva` |
| XP: revisão / streak / teto diário de revisões | `50` / `10` / `3` | `GamificacaoService` |
| Custo de nível | `600·n` XP | `GamificacaoService.progressoNivel` |
| Acertos para dominar questão | `2` (em datas diferentes) | `QuestaoErrada.acertosParaDominar` |
| Sidebar / donut / formato compacto | `1080 px` / `5 fatias` / `6000 min` | `app.dart`, `graficos.dart` |

### 4.3 Invariantes de domínio

1. **Cadeia de revisão nasce da conclusão de Aula**, nunca de sessão avulsa (`AulaService.aplicarSessao.concluiuAgora`). Uma cadeia por aula (dedupe por `aulaId` pendente).
2. **Reancoragem só empurra** — sessão retroativa nunca cria atraso fantasma.
3. **Nada de gamificação é persistido** — XP, nível e badges derivam 100% dos registros e são **monótonos** (pico histórico + tombstone de peso + teto diário de bônus).
4. **Sem dado ⇒ `null`, nunca zero inventado.** `taxa`, `ritmo`, `cobertura geral`, `prontidão` e `variação MoM/YoY` retornam `null` quando não há base.
5. **Peso ≥ 1** em `Materia` e `Topico` (invariante da média ponderada e da fila) — imposta no `fromJson`, não só na UI.
6. **Tombstone** em `Materia` e `RegistroHora` (`excluidaEm`/`excluidoEm`): o registro fica no box para um sync futuro propagar deletes, mas some do `state`.
7. **O grafo de tópicos é um DAG** — validado em `criariaCiclo` (pré-requisitos) e `podeMoverPara` (hierarquia).
8. **Um só motor de espaçamento** — revisões e caderno de erros compartilham `proximoPassoFsrs`.
9. **Um só ponto do ciclo** — `cicloPorUtilidade` alimenta Planejamento e Sugestão de hoje; `ParametrosCiclo` garante que a Prontidão projeta o mesmo modelo.
10. **Banca é dimensão canônica** — `Bancas.normalizar` aplicado na factory de `RegistroHora`, `QuestaoErrada`, `Simulado` e `ExecucaoProva`.

### 4.4 Tratamento de exceções (fluxo crítico → mitigação)

| Fluxo de erro crítico | Ação de mitigação |
|---|---|
| Hive não abre / migração falha no boot | `runApp(FalhaBootApp)` com passo, erro e stack copiáveis + botão "Tentar de novo" que reexecuta `iniciar()`; **nunca** sugere limpar dados |
| Erro assíncrono fora de `await` | `runZonedGuarded` → `FlutterError.presentError` |
| Erro de plataforma fora do zone | `platformDispatcher.onError` retorna `!kDebugMode` (release segue de pé, debug estoura) |
| Exceção em subárvore de widget | `ErrorWidget.builder = construirWidgetDeErro` |
| Registro corrompido no box | `_HiveRepositorio._carregar` isola por item (`debugPrint` + skip) — 1 registro ruim não derruba a coleção |
| `ExecucaoProva` corrompida | `ExecucaoProvaController.build` trata como "sem execução ativa" |
| Crash entre escritas multi-box (aula sem revisão) | `HiveBoxes.repararOrfaos()` em **todo** boot |
| Estado FSRS corrompido (`S ≤ 0` / `NaN`) | Saneamento na entrada de `proximoPassoFsrs` (cai na semente 3.0) — evitava `UnsupportedError` **depois** de a revisão já estar salva como feita |
| Falha no meio de `restaurarSubstituindo` | Snapshot pré-escrita reaplicado + erro repropagado; botão "Desfazer" enquanto o snapshot existir |
| Backup parcial usado para substituir | `StateError` no use case + bloqueio na tela (apagaria leituras/resumos/cronograma sem volta) |
| JSON de backup inválido | `FormatException` com contexto (campo/item) — nunca import parcial silencioso |
| `.xlsx` hostil (zip bomb, ref fora de limite, compressão exótica) | Tetos de 64 MB/arquivo e 50 MB/parte medidos em **bytes reais** durante a inflação; limites de linha/coluna do Excel; `FormatException` acionável |
| Linha de planilha inválida | Entra em `PlanilhaImportada.avisos` — **nunca descarte silencioso** |
| CSV aberto no Excel | `_semFormula` prefixa apóstrofo em `= + - @ \t \r` (CWE-1236) |
| Termo de busca degenerado | Teto de 300 chars + `try/catch` global devolvendo `[]` — a busca nunca lança |
| Notificações indisponíveis (web/desktop) | `NotificacoesService` é best-effort: flag `_pronto`, todos os métodos em `try/catch`; a tela de Revisões continua sendo a fonte de verdade |
| Wipe out | Trava dupla na UI (contagem exata + digitar `APAGAR`); irreversível e sem backup automático — documentado no use case |

---

## 5. Operação

```bash
flutter pub get
flutter analyze                              # gate bloqueante do CI
flutter test --exclude-tags screenshots      # 77 arquivos de teste (unit/widget/segurança/UAT)
flutter test --tags screenshots              # goldens (job separado, não bloqueia)
flutter run -d chrome                        # ou android/ios
```

- **CI** (`.github/workflows`): Flutter `3.44.8` fixado (canal `stable` flutuante quebraria o build sozinho). `dart format --set-exit-if-changed` está **fora** do gate de propósito — o código é *short style* (pré-Dart 3.7) e reformatar mexeria em 109/204 arquivos (8.024 linhas), apagando o `git blame` de um projeto cujo maior ativo são os comentários de decisão. Goldens rodam com `continue-on-error` (diferença de renderização por fonte/plataforma não deve treinar o time a ignorar build vermelho).
- **Deploy web** (`vercel.json`): clona o SDK no `buildCommand`, `flutter build web --release`, `outputDirectory: build/web`. Headers: HSTS, `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Permissions-Policy` (`camera=(self)` para a foto do caderno), COOP e **CSP** calibrada para CanvasKit (`script-src 'self' 'wasm-unsafe-eval' https://www.gstatic.com`, `object-src 'none'`, `frame-ancestors 'none'`). A fonte Display (Space Grotesk, OFL) é **asset local** justamente para não mexer nessa CSP.
- **Alvos:** Android, iOS, Web. `windows.disabled/` está desativado deliberadamente.
- **Manutenção:** `build/` é artefato gerado (git-ignorado, ~130 MB) e pode ser regenerado com `flutter build web`. O `git status` deste checkout mostra ~200 arquivos como *modified* com inserções == remoções — ruído de final de linha (CRLF/LF), não mudança real; revisar antes de qualquer commit em massa.
- **Documentação complementar.** Quatro documentos vivos ficam na raiz: `ROADMAP.md` (**fonte de verdade do estado atual** — leia este primeiro), `README.md`, `DEPLOY.md` e `SBOM.md` (inventário de dependências). Planos, relatórios de auditoria, ledgers e diagnósticos de ondas encerradas estão arquivados em [`docs/historico/`](docs/historico/README.md) — são registro do que foi decidido e por quê, **não** descrição do estado presente. Um plano arquivado que diz "aguardando autorização" está descrevendo o passado.
