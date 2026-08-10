# NÓ 9 — Plano: vazamento de controllers

Base: `3be7716`. **Planejado, não executado.**

---

## FASE 0 — Inventário completo

Varredura de 7 tipos (`TextEditingController`, `AnimationController`, `ScrollController`, `TabController`, `PageController`, `FocusNode`, `TransformationController`) em `lib/`, resolvendo **por nome de variável** contra os `.dispose()` do mesmo arquivo.

**66 controllers · 40 com dispose · 26 SEM.**

### Diagnóstico de uma frase

Os 26 vazamentos têm **forma única**: `TextEditingController` criado dentro de uma **função que abre diálogo**, usado no `showDialog`, nunca liberado. Nenhum `AnimationController`, `FocusNode`, `TabController`, `PageController` ou `ScrollController` vaza — todos vivem em `State` com `dispose()`.

### Grupo A — vazando (26)

| Arquivo | Tipo | Linha | Variável | Função | dispose | Risco |
|---|---|---|---|---|---|---|
| `materias/materia_dialog.dart` | TextEditing | 19 | `nome` | `mostrarDialogoMateria` | **não** | **alto** |
| | TextEditing | 20 | `peso` | idem | **não** | **alto** |
| | TextEditing | 21 | `questoes` | idem | **não** | **alto** |
| | TextEditing | 24 | `minimo` | idem | **não** | **alto** |
| | TextEditing | 27 | `notas` | idem | **não** | **alto** |
| | TextEditing | 29 | `horasAlvo` | idem | **não** | **alto** |
| `materias/importar_edital.dart` | TextEditing | 87 | `texto` | `mostrarImportarEdital` | **não** | **alto** |
| | TextEditing | 88 | `novaMateria` | idem | **não** | **alto** |
| `leituras/leituras_screen.dart` | TextEditing | 21 | `paginas` | `registrarSessaoLeitura` | **não** | **alto** |
| | TextEditing | 22 | `minutos` | idem | **não** | **alto** |
| | TextEditing | 147 | `titulo` | `_novaLeitura` | **não** | médio |
| | TextEditing | 148 | `pagInicio` | idem | **não** | médio |
| | TextEditing | 149 | `pagFim` | idem | **não** | médio |
| `revisoes/conclusao_revisao.dart` | TextEditing | 31 | `questoesCtrl` | `perguntarDesempenhoRevisao` | **não** | **alto** |
| | TextEditing | 32 | `acertosCtrl` | idem | **não** | **alto** |
| `aulas/aulas_screen.dart` | TextEditing | 27 | `nome` | `_dialogoAula` | **não** | médio |
| | TextEditing | 28 | `paginas` | idem | **não** | médio |
| `materias/topicos_screen.dart` | TextEditing | 26 | `nome` | `_dialogoTopico` | **não** | médio |
| | TextEditing | 27 | `notas` | idem | **não** | médio |
| `exportar/exportar_screen.dart` | TextEditing | 418 | `texto` | `_importarMesclando` | **não** | baixo |
| | TextEditing | 496 | `texto` | `_importarBackup` | **não** | baixo |
| `ambientes/ambientes_screen.dart` | TextEditing | 140 | `nome` | `_mostrarDialogo` | **não** | baixo |
| `mapa/mapa_estudos_screen.dart` | TextEditing | 340 | `controlador` | `_notaRapida` | **não** | baixo |
| `planejamento/planejamento_screen.dart` | TextEditing | 35 | `minutos` | `_editarDia` | **não** | baixo |
| `revisoes/revisoes_screen.dart` | TextEditing | 35 | `titulo` | `_novaRevisaoManual` | **não** | baixo |
| `configuracoes/configuracoes_screen.dart` | TextEditing | 260 | `controller` | `mostrarDialogoApagarDados` | **não** | baixo |

Risco = frequência de abertura × nº de controllers. `mostrarDialogoMateria` tem **5 call sites** e 6 controllers; `mostrarImportarEdital`, 4 call sites.

### Grupo B — corretos, não tocar (40)

| Arquivo | Tipos | Onde | dispose |
|---|---|---|---|
| `dashboard/confete_leve.dart` · `widgets/chama_streak.dart` | Animation ×2 | `State` | sim — **fora desta onda por decisão sua** |
| `busca/busca_screen.dart` | TextEditing + FocusNode | `_BuscaScreenState` | sim |
| `caderno/caderno_screen.dart` | Tab + TextEditing ×7 | `initState` | sim |
| `configuracoes/configuracoes_screen.dart` | TextEditing ×2 | `initState` | sim |
| `onboarding/onboarding_screen.dart` | Page | `State` | sim |
| `registro/registro_form.dart` | TextEditing ×7 + FocusNode | `State`/`initState` | sim |
| `resumos/resumos_screen.dart` | TextEditing | `_ResumoPageState` | sim |
| `simulados/prova_screen.dart` | TextEditing ×7 + FocusNode | 3 `State`s | sim |
| `simulados/simulados_screen.dart` | TextEditing ×7 + FocusNode | 2 `State`s | sim |

**Correção do meu próprio inventário:** o script marcou `configuracoes_screen.dart:260` como `fn build()`. É falso — o regex casou o `builder:` do `showDialog`. A linha está em `mostrarDialogoApagarDados`, função de diálogo. **Não** é criação por rebuild.

---

## FASE 1 — Planejamento

### Forma do conserto

13 das 14 funções fazem `await showDialog(...)`. Depois desse `await` o diálogo já foi desmontado e nenhum widget referencia mais o controller — liberar ali é correto e mínimo:

```dart
  await showDialog<void>(...);
  nome.dispose();
  peso.dispose();
```

**Nenhuma migração para `StatefulWidget`.** A regra do repo (`registro_form`, `prova_screen`, `simulados_screen`) é `State` para formulário de tela; diálogo efêmero não precisa disso, e converter 13 funções seria refatoração de arquitetura — proibida no escopo.

### Exceção — `perguntarDesempenhoRevisao`

Única que **não** faz `await`: `return showDialog<...>(...)`. Duas saídas:

| Opção | Forma |
|---|---|
| **A** *(recomendo)* | `.whenComplete(() { questoesCtrl.dispose(); acertosCtrl.dispose(); })` — preserva a assinatura e o retorno |
| B | Tornar `async`, guardar o resultado, dispor, retornar |

**A** é uma linha e não muda o tipo de retorno. **B** é mais legível para quem lê depois. Escolho **A** e registro a alternativa.

Este é o **débito declarado** em `conclusao_revisao.dart:26-28` — ele nomeia esta onda como responsável. Entra no escopo, como você previu.

### Grupos e ordem (alto → baixo)

| # | Grupo | Arquivos | Ctrls | Motivo do risco |
|---|---|---|---|---|
| 1 | Matérias | `materia_dialog` (6), `importar_edital` (2) | **8** | 5 e 4 call sites; maior densidade |
| 2 | Leituras | `leituras_screen` (5) | **5** | 2 diálogos no mesmo arquivo |
| 3 | Revisão | `conclusao_revisao` (2) | **2** | forma diferente (sem await); 2 call sites (tela + dashboard) |
| 4 | Cadastro | `aulas_screen` (2), `topicos_screen` (2), `exportar_screen` (2) | **6** | padrão idêntico ao grupo 1 |
| 5 | Avulsos | `ambientes`, `mapa`, `planejamento`, `revisoes_screen`, `configuracoes` | **5** | 1 controller cada |

### Riscos de regressão

| Risco | Avaliação |
|---|---|
| **Dispose prematuro** (liberar enquanto o diálogo vive) | É o **único** modo de falha real. Produz `A TextEditingController was used after being disposed`. Mitigado por posicionar o dispose SEMPRE depois do `await showDialog`, nunca dentro de `onPressed` |
| Controller capturado por widget que sobrevive ao diálogo | **Verificar por arquivo antes de editar.** `materia_dialog` usa `Autocomplete` (o `fieldController` dele é próprio do widget, não o nosso) — confirmar caso a caso |
| Fluxo com `await` interno antes do pop | Ex.: `_novaRevisaoManual` faz `await criarManual()` dentro do `onPressed`. O `.text` é lido ANTES do await, então dispor depois do `showDialog` externo é seguro |
| `mostrarDialogoApagarDados` | Captura `navigator`/`messenger` antes do `showDialog` e faz `await apagarTudo()` — o controller não é tocado depois do pop |
| Goldens | Nenhum. `dispose` não pinta |

### IMPEDIMENTO — não há como testar vazamento com o que existe hoje

Fui atrás do padrão da casa e **não existe**: zero teste de leak no repo.

| Caminho | Viabilidade |
|---|---|
| `testWidgets(experimentalLeakTesting:)` | API existe em 3.44.8, mas `LeakTesting` vem de `leak_tracker_flutter_testing` — dependência **transitiva**. Usar exigiria promovê-la a `dev_dependency` direta (mudança de `pubspec.yaml`), e a própria doc do Flutter marca como *"experimental and is not recommended"* |
| Observar o controller de fora | Impossível: são locais de função, sem superfície pública |
| Teste estrutural (varre o fonte) | Determinístico e sem dependência nova. Precedente meu no `card_plano_de_hoje` (garantia negativa) |

**Cobertura atual dos 14 diálogos: ZERO.** Nenhum teste exercita nenhuma dessas funções — conferido nome a nome. Isso significa que o modo de falha perigoso (dispose prematuro) **não seria pego** pela suíte.

**Proposta:** um teste estrutural em `test/dispose_dialogos_test.dart` que lê `lib/features/**/*.dart` e exige, para cada `TextEditingController` criado, um `.dispose()` da mesma variável no arquivo. Fecha a regressão sem dependência nova e sem API experimental.

**Decisão sua:** aceitar o teste estrutural, promover `leak_tracker_flutter_testing`, ou seguir sem teste (só o conserto).

### Critério de pronto

- `grep` de criação × dispose por variável: **0 sem par** em `lib/features/`.
- `flutter analyze` limpo e suíte verde após cada grupo — o verde importa porque dispose prematuro quebraria qualquer teste que abrisse o diálogo (hoje, nenhum abre; ver impedimento).
- Nenhum `StatefulWidget` criado; nenhum `State` alterado.

### Ordem interna de commits

Um commit por grupo, na ordem 1→5. O grupo 3 sai separado por ter forma distinta (`whenComplete`).

---

**PARADA — fim do planejamento.** Aguardando: (a) autorização, (b) decisão sobre o teste (estrutural / leak_tracker / nenhum).
