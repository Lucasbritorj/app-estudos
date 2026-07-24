# Prepara o repositório para deploy automático Vercel via GitHub.
# Rode UMA vez, do PowerShell, dentro de C:\Users\Lucas\Workspace\app_estudos
#
#   cd C:\Users\Lucas\Workspace\app_estudos
#   .\setup-github-deploy.ps1 -RepoUrl "https://github.com/<voce>/app-estudos.git"
#
# O que ele faz: solta o lock travado do git, fecha o commit das melhorias da
# auditoria (já normalizado por .gitattributes), aponta o remote e envia.

param(
  [Parameter(Mandatory = $true)][string]$RepoUrl,
  [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# 1) Lock órfão deixado por um `git add` interrompido. Só remova se NÃO houver
#    outro processo git rodando nesta pasta.
if (Test-Path ".git\index.lock") {
  Write-Host "Removendo .git\index.lock (lock órfão)..." -ForegroundColor Yellow
  Remove-Item ".git\index.lock" -Force
}

# 2) Normalização de fim de linha + arquivos novos da auditoria.
git add --renormalize .
git add .gitattributes vercel.json DEPLOY.md setup-github-deploy.ps1 `
        lib/domain/diagnostico_service.dart `
        lib/features/dashboard/widgets/card_diagnostico.dart `
        test/diagnostico_service_test.dart `
        test/correcoes_auditoria_test.dart

Write-Host "`n--- o que será commitado ---" -ForegroundColor Cyan
git diff --cached --stat

# 3) Commit.
$msg = @"
fix+feat: correções da auditoria 2026-07-24 + diagnóstico do dia

Correções (achado -> efeito):
- M-01 registro início==fim virava sessão de 24h fantasma
- M-03 conclusão antecipada consolidava como intervalo pleno no FSRS
- M-04 passo FSRS ignorava a nota da própria revisão
- M-11 reancoragem retroativa nascia atrasada; agora só empurra
- M-02 bônus de revisão ganhou teto diário (fim do farm de XP)
- M-05 ResultadoMateria sem invariantes (taxa >100% via import)
- M-09 sem teto de minutos por sessão (registro de 999999 min)
- U-12 localização pt-BR (date/time pickers falavam inglês)
- U-17 vírgula decimal nos 14 call sites que mostravam ponto

Feature: diagnóstico do dia — veredito honesto e acionável no topo do
dashboard, derivado dos agregados já memoizados (serviço puro + 13 testes).

Infra: .gitattributes normaliza EOL (o checkout Windows marcava 207
arquivos como modificados sem mudança real); vercel.json na raiz para
build do Flutter web na Vercel.

Validado: flutter analyze limpo, 382 testes verdes, build web release OK.
"@
git commit -m $msg

# 4) Remote + push.
if (git remote | Select-String -Quiet "^origin$") {
  git remote set-url origin $RepoUrl
} else {
  git remote add origin $RepoUrl
}
git branch -M $Branch
git push -u origin $Branch

Write-Host "`nPronto. Agora, em vercel.com:" -ForegroundColor Green
Write-Host "  Add New > Project > importe o repo > Framework Preset: Other"
Write-Host "  Nao mexa em Build/Output: o vercel.json da raiz ja define tudo."
Write-Host "  O primeiro build baixa o SDK do Flutter (leva ~5-8 min)."
