#!/usr/bin/env python3
"""Descarrega o py4godot e instala-o em <destino>/addons/.

Faz download do py4godot.zip e extrai apenas `install_dir/addons/` para
<destino>/addons/ (por omissão, a pasta onde este script está).
Se addons/py4godot/ já existir, não o volta a descarregar (a não ser que uses --force).

Depois instala as dependências de requirements.txt no Python do próprio
py4godot (instalando antes o pip, se faltar). É o Python dentro de
addons/py4godot/cpython-*/python/ que corre os scripts .py no Godot, por isso
é nele que as bibliotecas têm de estar. Pode correr-se outra vez a qualquer
altura: o que já estiver instalado não é descarregado de novo.

Requer: pip install tqdm

Uso:
    python download_addon.py
    python download_addon.py --force
    python download_addon.py --sem-deps          # não instala o requirements.txt
    python download_addon.py --url "<outro_url>" --dest "C:/caminho/projeto"
"""

import argparse
import platform
import shutil
import subprocess
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


def passo(n: int, total: int, texto: str) -> None:
    """Anuncia o passo atual, numa linha própria, por baixo de qualquer barra anterior."""
    tqdm.write(f"\n[{n}/{total}] {texto}")


def download(url: str, target: Path) -> None:
    """Descarrega `url` para o ficheiro `target`, com barra de progresso."""
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as resp, open(target, "wb") as out:
        total = int(resp.headers.get("Content-Length") or 0) or None  # None = tamanho desconhecido
        with tqdm(total=total, unit="B", unit_scale=True, unit_divisor=1024,
                  desc="Download", postfix=Path(url).name) as barra:
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
        barra = tqdm(membros, desc="A extrair", unit="ficheiro")
        for member in barra:
            barra.set_postfix_str(Path(member.filename).name[:40])   # ficheiro atual
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
            if (member.external_attr >> 16) & 0o111:   # mantém a permissão de execução (Linux/macOS)
                out_path.chmod(out_path.stat().st_mode | 0o111)
            count += 1
    return count


def python_do_addon(dest: Path) -> Path | None:
    """Devolve o executável de Python embebido no py4godot para este sistema, ou None."""
    base = dest / "addons" / "py4godot"
    if sys.platform.startswith("win"):
        sufixo = "windows64" if sys.maxsize > 2**32 else "windows32"
        nomes = ["python.exe"]
    elif sys.platform == "darwin":
        sufixo = "darwin64"
        nomes = ["bin/python3", "bin/python"]
    else:
        sufixo = "linuxarm64" if platform.machine().lower() in ("aarch64", "arm64") else "linux64"
        nomes = ["bin/python3", "bin/python"]
    for pasta in sorted(base.glob(f"cpython-*-{sufixo}")):
        for nome in nomes:
            exe = pasta / "python" / nome
            if exe.is_file():
                return exe
    return None


def instalar_dependencias(dest: Path, inicio: int = 1, total: int = 2) -> int:
    """Instala o requirements.txt no Python do py4godot (e o pip, se faltar). 0 = sucesso."""
    requisitos = dest / "requirements.txt"
    if not requisitos.is_file():
        print("Sem requirements.txt: nada para instalar.")
        return 0

    passo(inicio, total, "A preparar o pip no Python do py4godot")
    exe = python_do_addon(dest)
    if exe is None:
        print("Não encontrei o Python do py4godot em addons/py4godot/cpython-*/python/.\n"
              "Confirma que o addon foi instalado para o teu sistema.")
        return 1
    print(f"Python do py4godot: {exe}")

    if subprocess.run([str(exe), "-m", "pip", "--version"],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        get_pip = dest / "addons" / "py4godot" / "get_pip.py"
        if not get_pip.is_file():
            print(f"O pip não está instalado e falta {get_pip}.")
            return 1
        print("O pip não está instalado: a instalar (get_pip.py)...")
        if subprocess.run([str(exe), str(get_pip)]).returncode != 0:
            print("Falhou a instalação do pip.")
            return 1
    else:
        print("O pip já está instalado.")

    passo(inicio + 1, total, "A instalar as dependências do requirements.txt "
          "(pode demorar vários minutos: inclui o torch)")
    if subprocess.run([str(exe), "-m", "pip", "install", "-r", str(requisitos)]).returncode != 0:
        print("Falhou a instalação das dependências. Para tentar outra vez: python download_addon.py")
        return 1
    print("Dependências instaladas.")
    return 0


def main() -> int:
    """Lê os argumentos, descarrega o zip e instala os addons. Devolve o código de saída."""
    parser = argparse.ArgumentParser(description="Instala o addon py4godot no projeto.")
    parser.add_argument("--url", default=DEFAULT_URL, help="URL do py4godot.zip")
    parser.add_argument("--dest", default=str(Path(__file__).resolve().parent),
                        help="pasta do projeto Godot (por omissão, a deste script)")
    parser.add_argument("--sem-deps", action="store_true",
                        help="não instalar o requirements.txt no Python do py4godot")
    parser.add_argument("--force", action="store_true",
                        help="descarregar e substituir mesmo que addons/py4godot/ já exista")
    args = parser.parse_args()

    dest = Path(args.dest)
    dest.mkdir(parents=True, exist_ok=True)

    existing = dest / "addons" / "py4godot"
    if existing.exists() and not args.force:
        print(f"{existing} já existe (usa --force para o substituir).")
        return 0 if args.sem_deps else instalar_dependencias(dest)

    total = 2 if args.sem_deps else 4   # descarregar, extrair [, pip, dependências]
    with tempfile.TemporaryDirectory() as tmp:
        zip_path = Path(tmp) / "py4godot.zip"
        passo(1, total, "A descarregar o py4godot")
        try:
            download(args.url, zip_path)
        except Exception as e:
            print(f"Erro no download: {e}\n"
                  "Confirma o URL ou passa outro com --url.")
            return 1
        passo(2, total, "A extrair os ficheiros para addons/")
        n = extract_addons(zip_path, dest)

    if n == 0:
        print(f"Nada encontrado em '{PREFIX}' dentro do zip.")
        return 1
    print(f"{n} ficheiros extraídos para {dest / 'addons'}")
    return 0 if args.sem_deps else instalar_dependencias(dest, 3, total)


if __name__ == "__main__":
    sys.exit(main())