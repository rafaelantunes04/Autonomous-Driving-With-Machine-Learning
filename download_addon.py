#!/usr/bin/env python3
"""Descarrega o py4godot e instala-o em <destino>/addons/.

Faz download do py4godot.zip e extrai apenas `install_dir/addons/` para
<destino>/addons/ (por omissão, a pasta onde este script está).
Se addons/py4godot/ já existir, não faz nada (a não ser que uses --force).

Requer: pip install tqdm

Uso:
    python download_addon.py
    python download_addon.py --force
    python download_addon.py --url "<outro_url>" --dest "C:/caminho/projeto"
"""

import argparse
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

from tqdm import tqdm

# Release mais recente do py4godot no GitHub. Se mudar, usa --url.
DEFAULT_URL = "https://github.com/niklas2902/py4godot/releases/latest/download/py4godot.zip"

# Pasta dentro do zip que contém os addons
PREFIX = "install_dir/addons/"

# Tamanho dos blocos lidos em cada passo do download (bytes)
CHUNK = 64 * 1024


def download(url: str, target: Path) -> None:
    """Descarrega `url` para o ficheiro `target`, com barra de progresso."""
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as resp, open(target, "wb") as out:
        total = int(resp.headers.get("Content-Length") or 0) or None  # None = tamanho desconhecido
        with tqdm(total=total, unit="B", unit_scale=True, unit_divisor=1024,
                  desc="Download") as barra:
            while chunk := resp.read(CHUNK):
                out.write(chunk)
                barra.update(len(chunk))


def extract_addons(zip_path: Path, dest: Path) -> int:
    """Extrai só `install_dir/addons/` do zip para `dest/addons/`.

    Ignora caminhos que tentem sair de `dest`. Devolve o número de ficheiros extraídos.
    """
    dest = dest.resolve()
    count = 0
    with zipfile.ZipFile(zip_path) as zf:
        membros = [m for m in zf.infolist() if m.filename.startswith(PREFIX)]
        for member in tqdm(membros, desc="A extrair", unit="ficheiro"):
            rel = member.filename[len("install_dir/"):]  # -> "addons/..."
            if rel == "addons/":
                continue
            out_path = (dest / rel).resolve()
            if dest not in out_path.parents:
                continue  # proteção contra caminhos maliciosos
            if member.is_dir():
                out_path.mkdir(parents=True, exist_ok=True)
                continue
            out_path.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(member) as src, open(out_path, "wb") as dst:
                shutil.copyfileobj(src, dst)
            count += 1
    return count


def main() -> int:
    """Lê os argumentos, descarrega o zip e instala os addons. Devolve o código de saída."""
    parser = argparse.ArgumentParser(description="Instala o addon py4godot no projeto.")
    parser.add_argument("--url", default=DEFAULT_URL, help="URL do py4godot.zip")
    parser.add_argument("--dest", default=str(Path(__file__).resolve().parent),
                        help="pasta do projeto Godot (por omissão, a deste script)")
    parser.add_argument("--force", action="store_true",
                        help="descarregar e substituir mesmo que addons/py4godot/ já exista")
    args = parser.parse_args()

    dest = Path(args.dest)
    dest.mkdir(parents=True, exist_ok=True)

    existing = dest / "addons" / "py4godot"
    if existing.exists() and not args.force:
        print(f"{existing} já existe. Nada a fazer (usa --force para substituir).")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        zip_path = Path(tmp) / "py4godot.zip"
        try:
            download(args.url, zip_path)
        except Exception as e:
            print(f"Erro no download: {e}\n"
                  "Confirma o URL ou passa outro com --url.")
            return 1
        n = extract_addons(zip_path, dest)

    if n == 0:
        print(f"Nada encontrado em '{PREFIX}' dentro do zip.")
        return 1
    print(f"{n} ficheiros extraídos para {dest / 'addons'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())