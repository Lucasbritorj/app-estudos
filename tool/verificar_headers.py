#!/usr/bin/env python3
"""Confere se os headers que o `vercel.json` promete são os que produção entrega.

Motivo de existir: em 03/08/2026 o commit `bd11b38` corrigiu
`camera=()` -> `camera=(self)` numa CÓPIA do `vercel.json` (em `web/`), e
produção — que lê o da raiz — continuou bloqueando a câmera do caderno de
erros. O `DEPLOY.md` já avisava em negrito para editar os dois juntos. Aviso em
prosa não é controle; isto é.

Decisão de design que vale registrar: os valores esperados são LIDOS do
`vercel.json`, nunca redigitados aqui. Escrever a lista de headers de novo
neste arquivo recriaria exatamente a duplicata que o script existe para
detectar.

Uso:
    python3 tool/verificar_headers.py https://exemplo.com
    python3 tool/verificar_headers.py https://exemplo.com --config vercel.json

Saída: tabela por header. Código 0 se tudo bate, 1 se algo diverge.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

TIMEOUT = 20
FONTE_CURINGA = "/(.*)"


def headers_esperados(config: Path) -> dict[str, str]:
    """Extrai os headers da regra curinga do vercel.json."""
    dados = json.loads(config.read_text(encoding="utf-8"))
    for regra in dados.get("headers", []):
        if regra.get("source") == FONTE_CURINGA:
            return {h["key"]: h["value"] for h in regra.get("headers", [])}
    raise SystemExit(
        f"{config}: nenhuma regra de headers com source '{FONTE_CURINGA}'. "
        "O arquivo mudou de formato?"
    )


def buscar(url: str, metodo: str = "HEAD"):
    """Devolve (status, headers). Erro HTTP não é exceção: 404 é resposta."""
    req = urllib.request.Request(url, method=metodo, headers={"User-Agent": "verificar-headers/1"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, {k.lower(): v for k, v in r.headers.items()}
    except urllib.error.HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}


def normalizar(valor: str) -> str:
    """Compara sem se prender a espaçamento — `a=(), b=()` == `a=(),b=()`."""
    return " ".join(valor.replace(", ", ",").split())


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("url", help="URL de produção, com esquema")
    p.add_argument("--config", default="vercel.json", type=Path)
    args = p.parse_args()

    url = args.url.rstrip("/")
    esperados = headers_esperados(args.config)

    try:
        status, recebidos = buscar(url)
    except Exception as e:  # rede, DNS, TLS
        print(f"FALHA: não foi possível acessar {url} ({e})")
        return 1

    print(f"{url} -> HTTP {status}")
    print(f"conferindo {len(esperados)} headers declarados em {args.config}\n")

    divergentes = []
    for chave, esperado in esperados.items():
        recebido = recebidos.get(chave.lower())
        if recebido is None:
            divergentes.append((chave, esperado, "<ausente>"))
            marca = "FALTA"
        elif normalizar(recebido) != normalizar(esperado):
            divergentes.append((chave, esperado, recebido))
            marca = "DIVERGE"
        else:
            marca = "ok"
        print(f"  [{marca:>7}] {chave}")

    # A config nunca deve ser servida como asset público. Era o sintoma de que
    # existia uma cópia dentro de `build/web/`.
    status_config, _ = buscar(f"{url}/vercel.json", metodo="GET")
    config_exposta = status_config == 200
    print(f"\n  [{'FALHA' if config_exposta else 'ok':>7}] /vercel.json -> HTTP {status_config}")

    if divergentes or config_exposta:
        print("\n--- divergências ---")
        for chave, esperado, recebido in divergentes:
            print(f"{chave}\n  esperado: {esperado}\n  recebido: {recebido}")
        if config_exposta:
            print("/vercel.json responde 200 — a config está sendo servida como arquivo público.")
        return 1

    print("\nTodos os headers batem com o vercel.json.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
