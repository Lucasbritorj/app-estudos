# Ledger de execução — FASE 5

Estado vivo. Uma linha por item, atualizada antes de passar ao próximo.
Entrada: `PLANO_2026-08-03.md` (NÓ 4). Sessão de 03/08/2026.

## Verificação disponível nesta sessão

| Ferramenta | Disponível | Observação |
|---|---|---|
| Dart SDK 3.12.2 | **sim** | Instalado no sandbox (233 MB). Mesma versão do `pubspec.yaml` |
| Gate de parse (`dart format --output=none`) | **sim** | Exit 65 em erro de sintaxe, 0 em arquivo válido — comprovado |
| Fonte do Flutter 3.44.8 | **sim** | Clone esparso; usado para conferir cada API contra o SDK fixado |
| Servidor HTTP local | **sim** | Usado para testar o gate de headers ponta a ponta |
| `flutter analyze` | **não** | SDK completo = 1,55 GB + ~3,5 GB extraídos > 3,3 GB livres |
| `flutter test` | **não** | idem |
| Gradle / Android SDK | **não** | — |

**Consequência:** nenhum item abaixo está marcado verde. Estão marcados
**`pendente-de-execução`** — o código está escrito e passou por tudo que este
ambiente consegue provar, mas o gate real (`flutter analyze` + `flutter test`)
roda na sua máquina ou no runner.

## Status da lista de prioridades

| # | Item | P | Status | Verificado por execução | Falta |
|---|---|---|---|---|---|
| 1+5 | Blindar boot e erros de UI | P0 | **escrito** | parse OK · 11 APIs conferidas no SDK 3.44.8 · 1 erro de compilação encontrado e corrigido | `flutter test test/falha_boot_test.dart` |
| 2 | Unificar `vercel.json` | P0 | **escrito** | JSON válido · 1 único arquivo no repo · nenhuma referência órfã | redeploy + `curl -sI` |
| 3 | Gate de headers no CI | P0 | **escrito e testado** | script exercitado contra 3 servidores locais: correto→0, defeito de 03/08→1, config exposta→1 · YAML válido | definir `vars.URL_PRODUCAO` |
| 4 | Signing de release Android | P1 | **escrito** | `.gitignore` conferido por `git check-ignore` nos 3 padrões | criar keystore · `flutter build appbundle --release` |
| 6+10 | Dispose + Semantics em 10 telas | P1/P2 | **não executado** | — | ver justificativa abaixo |
| 7 | Atomicidade multi-box | P1 | **não executado** | — | é mudança arquitetural — excluída pela sua condição |
| 8 | `integration_test` | P1 | **não executado** | — | ver justificativa abaixo |
| 9 | Sincronizar docs | P2 | **parcial** | `DEPLOY.md` e `RELATORIO_AUDITORIA.md` corrigidos como parte do item 2 | `ROADMAP.md`, `README.md`, `SBOM.md` |
| 11 | B16 prova no backup | P2 | **não executado** | — | fora do recorte P0/P1 autorizado |
| 12 | Tema claro | P3 | **não executado** | — | por último, por invalidar os 19 goldens |

## Itens P1 deliberadamente não executados

**6+10 — dispose + Semantics em 10 telas.** Dois motivos independentes.
(a) O `PLANO_2026-08-03.md` §4.4 sequencia esta onda **depois** do
`integration_test`, porque são 10 arquivos de UI e a suíte atual é cega para
defeito de cruzamento. Executar agora é o mesmo erro que produziu `b5199c6` e
`bd11b38`, em escala maior. (b) São ~25 conversões de `ConsumerWidget` para
`StatefulWidget`, e a única verificação que tenho é parse — que não pega
`State` mal ligado, `dispose` chamado duas vezes ou controller usado depois de
liberado. Escrever 10 telas às cegas para você descobrir os erros é transferir
o custo, não resolver.

**8 — `integration_test`.** É o item de maior valor estrutural do plano e por
isso mesmo o pior candidato a ser escrito sem execução: são três fluxos que
atravessam Riverpod, Hive e navegação, e é exatamente onde a chance de eu
inventar uma assinatura de API é maior. Teste de integração que não compila é
pior que ausência de teste — dá sensação de rede sem rede.

Ambos ficam prontos para a próxima rodada, **depois** que a baseline da onda 0
rodar na sua máquina.

## Onda 0 — ainda pendente do seu lado

| Passo | Comando | Por quê |
|---|---|---|
| 0.1 | `Remove-Item .git\index.lock` | Existe agora (0 bytes). Bloqueia o próximo commit |
| 0.2 | `flutter analyze` | Gate real dos 4 itens acima |
| 0.3 | `flutter test --exclude-tags screenshots --reporter expanded` | Baseline + os 6 testes novos |
| 0.4 | `flutter test --tags screenshots` | Confirmar que os 19 goldens não mexeram |
| 0.5 | `curl -sI <dominio>` | Estado dos headers antes do redeploy |
| 0.6 | `.mailmap` | `Lucas Brito` e `Lucas` são a mesma pessoa |

Se 0.2 ou 0.3 vier vermelho, é a minha mudança — me traga a saída.
