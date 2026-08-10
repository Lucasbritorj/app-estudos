# NÓ 7 — Plano D-01: backup completo

Base: `d79b89c`. **Planejado, não executado.**

---

## FASE 0 — Contexto

| Arquivo | LOC | Papel |
|---|---|---|
| `lib/domain/export_service.dart` | 424 | `jsonCompleto` (linha 300), `jsonAmbiente` (367) |
| `lib/domain/import_service.dart` | ~190 | `BackupImportado`, `parseBackup` (linha 82) |
| `lib/application/backup_use_case.dart` | ~160 | `snapshotAtual` (30), `restaurarSubstituindo` (70), `_aplicarSubstituindo` (105) |
| `lib/features/exportar/exportar_screen.dart` | — | Botão "JSON — backup completo" (linha 199) |
| `lib/data/models/resumo.dart` · `configuracoes.dart` | — | Modelos |

**Testes:** `test/uat/uat_import_export_test.dart` (UAT-G1..G11), `test/backup_rollback_test.dart`, `test/backup_resumos_test.dart`, `test/export_service_test.dart`, `test/apagar_dados_test.dart`.

---

## Veredito: passos 1, 2, 3 e 5 já estão fechados. O furo está no 4.

Quarto item seguido em que a correção existe e o buraco mudou de porta. Não vou fabricar trabalho.

### Passo 2 — Resumos e Configurações no payload · **FECHADO**

| Campo | Onde é gravado |
|---|---|
| `resumos` | `export_service.dart:342` |
| `configuracoes` | `export_service.dart:353`, com comentário: *"faziam parte do 'backup completo' só no nome"* |
| `anexos` (fotos) | `export_service.dart:348` |

**Os três call sites de produção passam tudo:**

| Call site | resumos | configuracoes | anexos |
|---|---|---|---|
| `backup_use_case.dart:30-47` (snapshot de rollback) | ✅ | ✅ | ✅ |
| `exportar_screen.dart:199-213` (botão do usuário) | ✅ | ✅ | ✅ |
| `export_service.dart:387` (`jsonAmbiente`) | n/a — parcial por design, marca `escopo` | n/a | ✅ |

Procurei aqui o furo tipo-D-04 (serviço corrigido, chamador desatualizado). **Não existe.**

### Passo 3 — Import tolerante · **FECHADO**

`import_service.dart:167-168` — *"Backups antigos não têm 'resumos' — lista() devolve vazio."*
`import_service.dart:173-181` — `configuracoes` tolerante.
Coberto por `backup_resumos_test.dart` (2º teste) e **UAT-G3**.

### Passo 5 — Round-trip · **FECHADO**

`backup_resumos_test.dart` cobre ida e volta de resumos (texto, `doCatalogo`, `atualizadoEm`). UAT-G1 (round-trip sem perda), G11 (carimbo de conclusão).

---

## Passo 4 — o furo real: tolerância no parse vira destruição na restauração

### Diagnóstico

`import_service.dart:64`:

```dart
bool get parcial => escopo != null;
```

`parcial` responde "veio de `jsonAmbiente`?", não "o payload está completo?". Backup antigo, gerado antes de existir a chave `resumos`, **não tem `escopo`** → `parcial == false` → `restaurarSubstituindo` aceita.

E `parseBackup` não distingue **chave ausente** de **lista vazia**: `lista('resumos', ...)` devolve `[]` nos dois casos.

O encontro dos dois em `_aplicarSubstituindo:128`:

```dart
await _ref.read(resumosProvider.notifier).substituirTudo(backup.resumos);
```

**Sem guarda.** Restaurar um backup pré-D-01 em modo "substituir" **apaga todas as páginas de resumo do usuário**, em silêncio.

O contraste está no mesmo método, 13 linhas abaixo (`:140-144`):

```dart
// Preferências só são tocadas quando o arquivo as traz: backup antigo (sem
// a chave) não pode zerar a meta semanal de quem está restaurando.
final preferencias = backup.configuracoes;
if (preferencias != null) { ... }
```

`configuracoes` é `Configuracoes?` — nulo distingue ausente de vazio, e a guarda existe. As **listas** não têm esse luxo, e nenhuma tem guarda.

**A ironia:** o comentário de `backup_resumos_test.dart:9-12` diz que o D-01 nasceu porque *"o diálogo de wipe manda exportar backup antes de apagar"*. Quem tem o backup mais antigo é exatamente quem mais precisa restaurar — e é quem perde os resumos.

### Alcance: não é só `resumos`

Toda coleção cuja chave foi adicionada depois de algum backup existir tem o mesmo risco. Por ordem de entrada no formato:

| Coleção | `substituirTudo` sem guarda | Backup antigo que não a tinha |
|---|---|---|
| `resumos` | `:128` | pré-D-01 |
| `questoesErradas` | `:130` | pré-caderno de erros (`f083c13`, 31/07) |
| `anexos` | `:133` | pré-F1 (fotos) |
| `simulados` | `:126` | pré-simulados |
| `ambientes` | `:109` | mitigado por `ambientesOuGeral()` — **já tem tratamento** |
| `materias`/`topicos`/`aulas`/`registros`/`revisoes`/`leituras`/`planejamento` | `:117-137` | existem desde a versão 1 — risco teórico |

`ambientes` prova que o padrão de guarda já foi reconhecido uma vez (`ambientesOuGeral`), só não foi generalizado.

### Duas leituras do passo 4 — decisão de produto

**Leitura A — "parcial deve virar true quando faltam chaves".**
Rejeito, e explico: quebraria UAT-G3 (backup antigo tem de continuar importável) e bloquearia também a mescla, que hoje funciona bem com backup antigo. `parcial` significa "escopo reduzido, gerado por `jsonAmbiente`"; sobrecarregar o termo piora.

**Leitura B — "restauração destrutiva não pode apagar o que o arquivo não menciona"** *(recomendo)*.
`parseBackup` passa a registrar quais chaves vieram no arquivo; `_aplicarSubstituindo` pula `substituirTudo` das coleções ausentes — exatamente o que `configuracoes` já faz. Backup honesto com lista vazia continua zerando (o usuário não tem nada mesmo); backup que **não fala** do assunto não decide sobre ele.

### Mudança mínima (leitura B)

| Arquivo | ~Linhas | Motivo |
|---|---|---|
| `lib/domain/import_service.dart` | ~12 | `BackupImportado` ganha `Set<String> chavesPresentes`; `parseBackup` registra o que o arquivo trouxe |
| `lib/application/backup_use_case.dart` | ~25 | `_aplicarSubstituindo` só substitui coleção cuja chave veio no arquivo |
| `test/backup_resumos_test.dart` | ~35 | Contraprova: restaurar backup pré-D-01 não apaga resumos existentes |
| `test/uat/uat_import_export_test.dart` | ~25 | UAT-G12: restauração de backup antigo preserva o que ele não menciona |

**Não é mudança de schema:** `chavesPresentes` é metadado de parse, nunca serializado. O formato do arquivo não muda, `versao` continua 1.

### Riscos e regressões

| Teste | Risco | Por quê |
|---|---|---|
| **UAT-G1** (round-trip sem perda) | baixo | Backup completo traz todas as chaves → todas substituem, como hoje |
| **UAT-G3** (tolerância a backup antigo) | **médio** | Hoje afirma que parseia sem exceção. Continua verdade; pode ganhar asserção nova |
| **UAT-G6** (backup de 1 ambiente é parcial) | baixo | `parcial` não muda de definição |
| **UAT-G2** (rejeições explícitas) | baixo | Não toco em validação |
| `backup_rollback_test.dart` | **médio** | O snapshot de rollback é gerado por `snapshotAtual()`, que traz **todas** as chaves → comportamento idêntico. Precisa de verificação |
| `apagar_dados_test.dart` | baixo | Wipe não passa por `_aplicarSubstituindo` |
| Restaurar backup COMPLETO onde o usuário apagou tudo de um tipo | **atenção** | Lista vazia presente ≠ ausente: continua zerando. É o comportamento correto e precisa de teste explícito para não regredir depois |

### Critério de pronto

- Restaurar (substituindo) um backup **sem** a chave `resumos` preserva os resumos existentes.
- Restaurar um backup **com** `"resumos": []` zera os resumos — o arquivo falou, e falou vazio.
- Mesma dupla de casos para `questoesErradas`, `anexos` e `simulados`.
- UAT-G1/G2/G3/G6 verdes sem alteração de expectativa.
- `snapshotAtual()` → `_aplicarSubstituindo` continua idêntico (o snapshot traz tudo).

### Ordem interna de commits

1. `test:` contraprova — restaurar backup pré-D-01 apaga resumos (vermelho)
2. `feat(import):` `parseBackup` registra as chaves presentes
3. `fix(D-01):` restauração destrutiva não apaga coleção ausente do arquivo
4. `test(uat):` UAT-G12 + os pares presente-vazio vs ausente

---

## Resumo

| Passo | Estado | Trabalho |
|---|---|---|
| 1 — mapear export vs domínio | feito neste plano | — |
| 2 — Resumos e Configurações no payload | **fechado** (`:342`, `:353`), 3 call sites conferidos | nenhum |
| 3 — import tolerante | **fechado** (`:167`, `:173`), UAT-G3 | nenhum |
| 4 — `parcial` honesto | **furo real**: tolerância no parse vira wipe na restauração | ~62 linhas, 4 arquivos |
| 5 — round-trip | **fechado** (`backup_resumos_test`, UAT-G1/G11) | nenhum |

**PARADA — fim do planejamento.** Aguardando: (a) autorização, (b) confirmação da leitura B para o passo 4.
