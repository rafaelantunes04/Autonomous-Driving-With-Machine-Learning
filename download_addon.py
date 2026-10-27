#!/usr/bin/env python3
"""
Faz download do py4godot.zip e extrai apenas install_dir/addons/ para
<destino>/addons/ (por omissão, a pasta onde este script está).
Se addons/py4godot/ já existir, não faz nada (a não ser que uses --force).

Uso:
    python download_py4godot.py
    python download_py4godot.py --force
    python download_py4godot.py --url "<outro_url>" --dest "C:/caminho/projeto"
"""

import argparse
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

DEFAULT_URL = (
    "https://release-assets.githubusercontent.com/github-production-release-asset/"
    "366836572/216a4f79-c712-4837-af2c-1fae47ea9e20?sp=r&sv=2018-11-09&sr=b&spr=https"
    "&se=2026-10-27T15%3A28%3A46Z&rscd=attachment%3B+filename%3Dpy4godot.zip"
    "&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0"
    "&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-10-27T14%3A28%3A37Z"
    "&ske=2026-10-27T15%3A28%3A46Z&sks=b&skv=2018-11-09"
    "&sig=PzPoUqTAE0VaseXFh3RZGj0u5yXgNNhLD3xvWdd%2Bbn8%3D"
    "&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc5MzExNDkxNywibmJmIjoxNzkzMTExMzE3LCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.w5i4bHheew-nfUtdYkyB_8-O-PtpbX6hHn4D5Ean6jo"
    "&response-content-disposition=attachment%3B%20filename%3Dpy4godot.zip"
    "&response-content-type=application%2Foctet-stream"
)

PREFIX = "install_dir/addons/"


def download(url: str, target: Path) -> None:
    print("A fazer download...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as resp, open(target, "wb") as out:
        shutil.copyfileobj(resp, out)
    print(f"Download concluído ({target.stat().st_size / 1_048_576:.1f} MB)")


def extract_addons(zip_path: Path, dest: Path) -> int:
    dest = dest.resolve()
    count = 0
    with zipfile.ZipFile(zip_path) as zf:
        for member in zf.infolist():
            name = member.filename
            if not name.startswith(PREFIX):
                continue
            rel = name[len("install_dir/"):]  # -> "addons/..."
            if not rel or rel == "addons/":
                continue
            out_path = (dest / rel).resolve()
            if dest not in out_path.parents and out_path != dest:
                continue  # proteção contra paths maliciosos
            if member.is_dir():
                out_path.mkdir(parents=True, exist_ok=True)
                continue
            out_path.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(member) as src, open(out_path, "wb") as dst:
                shutil.copyfileobj(src, dst)
            count += 1
    return count


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--dest", default=str(Path(__file__).resolve().parent))
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
                  "O link assinado do GitHub expira ao fim de ~1 hora; "
                  "gera um novo na página de releases e usa --url.")
            return 1
        n = extract_addons(zip_path, dest)

    if n == 0:
        print(f"Nada encontrado em '{PREFIX}' dentro do zip.")
        return 1
    print(f"{n} ficheiros extraídos para {dest / 'addons'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())