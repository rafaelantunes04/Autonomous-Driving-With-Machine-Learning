"""Leitura/escrita dos modelos. O JSON PPO guarda pesos, não o otimizador."""
import json
import os
from ml.modelos.ppo_modelo import estado_ppo_mlp, carregar_estado

def guardar(modelo, nome_modelo, destino):
	"""Escreve o modelo no disco (o ppo_mlp em JSON, os outros em .zip do SB3)."""
	if nome_modelo == "ppo_mlp":
		tmp = destino + ".json.tmp"
		with open(tmp, "w", encoding="utf-8") as f:
			json.dump(estado_ppo_mlp(modelo), f)
		os.replace(tmp, destino + ".json")   # troca atómica: nunca fica um JSON a meio
		print("[treino_ppo] pesos guardados:", destino + ".json", flush=True)
	elif nome_modelo == "sac_mlp":
		from ml.modelos.sac_modelo import exportar
		# ZIP: redes e otimizadores; replay: experiências; JSON: condução.
		modelo.save(destino + ".tmp.zip")
		modelo.save_replay_buffer(destino + ".replay.tmp.pkl")
		with open(destino + ".json.tmp", "w", encoding="utf-8") as f:
			json.dump(exportar(modelo), f, allow_nan=False)
		os.replace(destino + ".tmp.zip", destino + ".zip")
		os.replace(destino + ".replay.tmp.pkl", destino + ".replay.pkl")
		os.replace(destino + ".json.tmp", destino + ".json")
		print("[SAC] Guardados checkpoint, replay buffer e ator JSON:", destino, flush=True)
	else:
		modelo.save(destino)
		print("[treino_ppo] modelo guardado:", destino + ".zip", flush=True)


def carregar_json(destino):
	"""Lê o JSON de pesos de `destino` (sem extensão)."""
	caminho = destino + ".json"
	if not os.path.isfile(caminho):
		raise FileNotFoundError("Não há %s para continuar" % caminho)
	with open(caminho, encoding="utf-8") as f:
		return json.load(f)
