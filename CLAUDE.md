@AGENTS.md

# CLAUDE.md — app-estudos

## Classe e objetivo

- **Classe: produto** (PWA publicada em app-estudos-neon.vercel.app, dados só no aparelho).
  Piso: CI verde (`flutter analyze`, testes, goldens no Windows), sem vulnerabilidade alta, sem
  segredo, e o bundle novo conferido no navegador após deploy (o service worker serve o antigo;
  checar o `main.dart.js`).
- **Objetivo: não declarado.** Falta o Lucas dizer o concurso-alvo, o prazo e a fricção diária.
  Até lá, só manutenção do piso; os itens de `ROADMAP.md` ficam no backlog sem executar.

## Comandos
- rodar: `flutter run -d chrome` · testar: `flutter test` · análise: `flutter analyze` ·
  goldens: `flutter test --tags screenshots` (geradas no Windows; CI roda em `windows-latest`).
- build: a Vercel faz pelo `vercel.json` (ver `DEPLOY.md`); local, `flutter build web`.
- publicar: merge na `main` publica na Vercel. Só por PR com CI verde e ok do Lucas.

## Decisões
- 2026-09-30 Cesgranrio removida das fontes de concursos: responde 403 à Vercel (PR #5).
- 2026-09-30 Job de goldens roda em Windows, onde as referências são geradas (PR #4).
- 2026-09-30 Classe produto declarada; objetivo pendente (concurso-alvo, prazo, fricção).
