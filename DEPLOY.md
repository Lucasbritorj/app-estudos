# Deploy — app-estudos (Vercel via GitHub)

Rota escolhida: **repositório no GitHub + deploy automático a cada push**.

## Bloqueio atual (1 minuto para resolver)

Um `git add` interrompido deixou um lock órfão em `.git\index.lock`, e o
sandbox onde trabalhei não tem permissão para apagar arquivos na sua pasta.
Enquanto ele existir, o git recusa qualquer escrita no índice.

O script `setup-github-deploy.ps1` remove esse lock e faz o resto. **Confira
antes que não há nenhum processo git rodando nesta pasta** (VS Code com
Source Control aberto costuma ser o culpado).

## Passo a passo

1. Crie um repositório vazio no GitHub (sem README, sem .gitignore).
2. No PowerShell:

   ```powershell
   cd C:\Users\Lucas\Workspace\app_estudos
   .\setup-github-deploy.ps1 -RepoUrl "https://github.com/<voce>/app-estudos.git"
   ```

   O script: solta o lock → normaliza fim de linha → adiciona os arquivos
   novos → commita as correções da auditoria → aponta o remote → dá push.

3. Em [vercel.com](https://vercel.com): **Add New → Project** → importe o
   repositório → **Framework Preset: Other**. Não preencha Build Command nem
   Output Directory: o `vercel.json` da raiz já define os dois.

4. Deploy. O primeiro build clona o SDK do Flutter (**~5 a 8 min**); os
   seguintes reaproveitam o cache da Vercel e ficam bem mais rápidos.

## Como o build funciona na Vercel

A imagem de build da Vercel não tem Flutter, então o `vercel.json` da raiz
clona o SDK na versão exata usada aqui (3.44.8) e compila:

```
git clone --depth 1 --branch 3.44.8 https://github.com/flutter/flutter.git
flutter/bin/flutter config --enable-web
flutter/bin/flutter pub get
flutter/bin/flutter build web --release --no-wasm-dry-run
→ outputDirectory: build/web
```

**Verificado nesta sessão**: rodei essa mesma sequência num clone limpo do
projeto, com ambiente enxuto (`env -i`) e o SDK acessado só por caminho
relativo. O `main.dart.js` saiu com exatamente o mesmo tamanho do build
oficial (6.330.067 bytes). O único passo não executado aqui foi o `git clone`
do SDK (1,5 GB não cabia na janela de tempo do sandbox) — é o passo padrão e
de menor risco da receita.

**Atenção**: os headers de segurança (HSTS, CSP calibrada para CanvasKit,
X-Frame-Options etc.) foram movidos para o `vercel.json` da **raiz**. Quando
existe um na raiz, a Vercel ignora o de `build/web/` — se você editar um,
edite o outro junto ou os headers somem em produção.

## Alternativa: deploy manual do artefato pronto

`build/web/` já contém um build de produção válido e está linkado ao projeto
`app-estudos`:

```powershell
cd C:\Users\Lucas\Workspace\app_estudos\build\web
npx vercel --prod
```

Nesse caminho vale o `vercel.json` de dentro de `build/web/`, e o SDK não é
clonado (sobe o artefato já compilado).

## Estado verificado nesta sessão

| Verificação | Resultado |
|---|---|
| `flutter analyze` | No issues found! |
| `flutter test` | 382 testes, todos verdes |
| `flutter build web --release` | ✓ Built build/web (35,9s · 45 MB) |
| Receita de build da Vercel | sequência executada, `main.dart.js` idêntico |

Flutter 3.44.8 / Dart 3.12.2 — a mesma versão fixada no `vercel.json`.

## Depois de qualquer mudança no código

```powershell
flutter analyze
flutter test
git add -A; git commit -m "..."; git push
```

O push dispara o deploy sozinho.
