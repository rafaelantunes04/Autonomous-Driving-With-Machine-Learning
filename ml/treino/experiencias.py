"""Pastas únicas e proveniência das experiências, sem depender do Godot."""
from datetime import datetime, timezone
from importlib.metadata import version, PackageNotFoundError
from pathlib import Path
import hashlib
import json
import os
import platform
import subprocess
import uuid


def escrever_json(caminho, dados):
    caminho = Path(caminho)
    tmp = caminho.with_name(caminho.name + ".tmp")
    tmp.write_text(json.dumps(dados, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")
    os.replace(tmp, caminho)


def sha256(caminho):
    h = hashlib.sha256()
    with open(caminho, "rb") as f:
        for parte in iter(lambda: f.read(1024 * 1024), b""):
            h.update(parte)
    return h.hexdigest()


def nova_execucao(base, grupo):
    nome = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "_" + uuid.uuid4().hex[:8]
    pasta = Path(base) / grupo / nome
    pasta.mkdir(parents=True, exist_ok=False)
    return pasta


def proveniencia(projeto):
    projeto = Path(projeto)
    versoes = {}
    for nome in ("torch", "numpy", "stable-baselines3", "sb3-contrib", "gymnasium", "tensorboard"):
        try:
            versoes[nome] = version(nome)
        except PackageNotFoundError:
            versoes[nome] = None
    fontes = list((projeto / "ml").rglob("*.py")) + list(projeto.glob("*.py")) + list((projeto / "scripts").rglob("*.gd"))
    fontes += list((projeto / "cenas").glob("*.tscn")) + list((projeto / "configuracoes").glob("*.json"))
    git = {}
    for nome, args in (("commit", ["rev-parse", "HEAD"]), ("alteracoes", ["status", "--porcelain"])):
        try:
            git[nome] = subprocess.check_output(["git", "-C", str(projeto), *args], stderr=subprocess.DEVNULL, timeout=5).decode().strip()
        except (OSError, subprocess.SubprocessError):
            git[nome] = "indisponivel"
    return {"utc": datetime.now(timezone.utc).isoformat(), "python": platform.python_version(),
            "bibliotecas": versoes, "git": git,
            "fontes_sha256": {str(p.relative_to(projeto)).replace("\\", "/"): sha256(p) for p in fontes}}
