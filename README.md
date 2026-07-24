# app_estudos — Meu Caminho Aprovado

App Flutter **local-first** (Hive CE, sem backend/rede) para planejamento de
estudos para concursos: matérias/tópicos, ciclo de revisões com FSRS,
cronômetro de sessões, simulados, dashboard de desempenho (heatmap de
constância, retenção real, forecast de revisão) e export para Power BI
(modelo estrela zipado). Import de edital e de planilha `.xlsx` de estudos.

**Stack:** Flutter (Dart 3.12) · Riverpod 3 · Hive CE (persistência local) ·
fl_chart · deploy web estático (Vercel).

**Alvos de plataforma:** Android, iOS, Web. `windows.disabled/` existe mas
está desativado deliberadamente (não é alvo de build atual).

## Rodando localmente

```
flutter pub get
flutter test        # suíte de testes (unit + segurança)
flutter analyze      # lint
flutter run -d chrome # ou android/ios
```

## Documentação de auditoria

O projeto passou por uma auditoria autônoma de segurança/qualidade (skill
`security-audit-loop`). Ver:

- [`RELATORIO_AUDITORIA.md`](RELATORIO_AUDITORIA.md) — achados 5W2H, severidade e correções
- [`LEDGER_DE_AUDITORIA.md`](LEDGER_DE_AUDITORIA.md) — estado vivo da auditoria
- [`SBOM.md`](SBOM.md) — inventário de dependências (pubspec.lock)

## Notas de manutenção

- `build/` é artefato gerado (git-ignorado); pode ser apagado e regenerado
  com `flutter build web` sem perda — hoje ocupa ~130 MB em disco.
- O `git status` deste checkout mostra ~200 arquivos como "modified" com
  inserções == remoções em cada um — é ruído de final de linha (CRLF/LF)
  do checkout neste ambiente, não mudança de conteúdo real. Não commitado
  intencionalmente; revisar antes de qualquer commit em massa.
