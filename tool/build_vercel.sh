#!/usr/bin/env bash
# Build da web na Vercel.
#
# Este script existe porque o `buildCommand` do vercel.json passou a ser
# validado em 256 caracteres: o comando inline tinha 327 e o deploy começou a
# ser REJEITADO na validação de schema, antes de qualquer build rodar
# (`dpl_Cb5V1byJeTQZRoWAkWJ26epf7xtJ`, 05/08/2026). O mesmo arquivo buildava
# normalmente em 27/07 — o limite é novo, o comando não mudou.
#
# A imagem de build da Vercel não traz Flutter, então o SDK é clonado aqui na
# versão EXATA usada no projeto. Fixada de propósito: canal `stable` flutuante
# faria o build quebrar sozinho num dia em que ninguém mexeu no código.
set -euo pipefail

VERSAO_FLUTTER='3.44.8'

# Cache da Vercel pode trazer o diretório de um build anterior; nesse caso só
# reposiciona na tag em vez de clonar de novo.
if [ -d flutter ]; then
  cd flutter
  git fetch --depth 1 origin "$VERSAO_FLUTTER"
  git checkout FETCH_HEAD
  cd ..
else
  git clone --depth 1 --branch "$VERSAO_FLUTTER" \
    https://github.com/flutter/flutter.git
fi

flutter/bin/flutter config --enable-web
flutter/bin/flutter pub get
# `--no-wasm-dry-run`: o dry-run de wasm falha em dependências que não são
# compatíveis e não agrega nada ao build JS que é o que vai para produção.
flutter/bin/flutter build web --release --no-wasm-dry-run
