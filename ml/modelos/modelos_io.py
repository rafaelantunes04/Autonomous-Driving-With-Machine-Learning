"""Checkpoints de treino e atores de condução. Os ficheiros são substituídos atomicamente."""
import json
import os
import shutil
from pathlib import Path
from ml.modelos.ppo_modelo import estado_ppo_mlp, carregar_estado


def extensoes(nome_modelo):
	if nome_modelo == "sac_mlp":
		return (".zip", ".replay.pkl", ".json")
	if nome_modelo == "ppo_mlp":
		return (".zip", ".json")
	if nome_modelo == "ppo_lstm":
		return (".zip",)
	raise ValueError("Modelo desconhecido: " + nome_modelo)


def guardar(modelo, nome_modelo, destino):
	destino = str(destino)
	extensoes(nome_modelo)
	Path(destino).parent.mkdir(parents=True, exist_ok=True)
	modelo.save(destino + ".tmp.zip")
	os.replace(destino + ".tmp.zip", destino + ".zip")
	dados = None
	if nome_modelo == "ppo_mlp":
		dados = estado_ppo_mlp(modelo)
	elif nome_modelo == "sac_mlp":
		from ml.modelos.sac_modelo import exportar
		modelo.save_replay_buffer(destino + ".replay.tmp.pkl")
		os.replace(destino + ".replay.tmp.pkl", destino + ".replay.pkl")
		dados = exportar(modelo)
	if dados is not None:
		with open(destino + ".json.tmp", "w", encoding="utf-8") as f:
			json.dump(dados, f, allow_nan=False)
		os.replace(destino + ".json.tmp", destino + ".json")
	print("[modelos] Guardado:", destino, flush=True)


def publicar(origem, destino, nome_modelo):
	"""Atualiza os ficheiros que as cenas de condução usam, mantendo o arquivo da execução."""
	Path(destino).parent.mkdir(parents=True, exist_ok=True)
	for ext in extensoes(nome_modelo):
		shutil.copyfile(str(origem) + ext, str(destino) + ext + ".tmp")
		os.replace(str(destino) + ext + ".tmp", str(destino) + ext)


def carregar_json(destino):
	with open(str(destino) + ".json", encoding="utf-8") as f:
		return json.load(f)
