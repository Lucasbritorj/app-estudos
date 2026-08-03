# Deploy — app-estudos (Vercel via GitHub)

Rota escolhida: **repositório no GitHub + deploy automático a cada push**.

## Estado do setup

Concluído. O remote `origin` aponta para
`https://github.com/Lucasbritorj/app-estudos.git` e `main` está sincronizada.
O `setup-github-deploy.ps1` foi um script de mão única para o primeiro push —
não é mais necessário.

Na Vercel: **Framework Preset: Other**, sem Build Command e sem Output
Directory preenchidos — o `vercel.json` da raiz define os dois. O primeiro
build clona o SDK do Flutter (**~5 a 8 min**); os seguintes reaproveitam o
cache.

## Se o `.git\index.lock` reaparecer

Um `git add` interrompido deixa um lock órfão em `.git\index.lock` e o git
passa a recusar qualquer escrita no índice — inclusive `git commit`. Já
aconteceu duas vezes neste projeto.

```powershell
Remove-Item .git\index.lock
```

**Feche o Source Control do VS Code antes de investigar** — é a causa mais
comum de um processo git segurando o índice.

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

## Headers de segurança — um arquivo, um caminho

Existe **um único** `vercel.json`, na raiz do repositório. Ele carrega os 7
headers (HSTS, CSP calibrada para CanvasKit, X-Frame-Options, COOP,
Referrer-Policy, X-Content-Type-Options, Permissions-Policy) e a receita de
build.

Isso é deliberado e substitui o arranjo anterior, que tinha uma cópia em
`web/vercel.json`. O arranjo antigo falhou na prática em 03/08: o commit
`bd11b38` corrigiu `camera=()` → `camera=(self)` na cópia, e produção — que lê
a raiz — continuou bloqueando a câmera do caderno de erros. Este próprio
arquivo já avisava, em negrito, para editar os dois juntos. O aviso não
bastou; a duplicata foi removida.

Consequência prática: **o deploy manual do artefato pronto
(`cd build/web && npx vercel --prod`) não é mais um caminho suportado.** Ele
subia sem os headers da raiz, o que fazia a postura de segurança do app
depender de qual comando tinha sido digitado por último. Deploy é só por
`git push`.

O gate `verificar-headers` do CI confere os 7 headers na URL de produção
depois de cada deploy — se algum divergir, o build fica vermelho.

## Verificação da receita de build (24/07/2026)

| Verificação | Resultado |
|---|---|
| `flutter build web --release` | ✓ Built build/web (35,9s · 45 MB) |
| Receita de build da Vercel | sequência executada em clone limpo com `env -i`; `main.dart.js` saiu com o mesmo tamanho do build oficial (6.330.067 bytes) |

Flutter 3.44.8 / Dart 3.12.2 — a mesma versão fixada no `vercel.json` e no
`ci.yml`.

As contagens de `flutter analyze` e `flutter test` saíram desta tabela de
propósito: números escritos à mão envelhecem em silêncio (a linha anterior
dizia "382 testes" quando o repositório já tinha 740 declarações). A fonte de
verdade é o último run verde do workflow **CI** na aba Actions do
repositório.

## Depois de qualquer mudança no código

```powershell
flutter analyze
flutter test
git add -A; git commit -m "..."; git push
```

O push dispara o deploy sozinho.
