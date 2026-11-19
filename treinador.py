"""Gestão comum dos treinos PPO, RecurrentPPO e SAC.

Recebe um ambiente Gymnasium; não depende de nós nem de classes do Godot.
Mantém os formatos e opções de gravação existentes: PPO-MLP em JSON,
SAC e PPO-LSTM em ZIP. Retomar por JSON repõe pesos, não o otimizador.
"""

import json
import os
import shutil
import traceback
import torch

from ppo_modelo import estado_ppo_mlp, carregar_estado

def _guardar(modelo, nome_modelo, destino):
	"""Escreve o modelo no disco (o ppo_mlp em JSON, os outros em .zip do SB3)."""
	if nome_modelo == "ppo_mlp":
		tmp = destino + ".json.tmp"
		with open(tmp, "w", encoding="utf-8") as f:
			json.dump(estado_ppo_mlp(modelo), f)
		os.replace(tmp, destino + ".json")   # troca atómica: nunca fica um JSON a meio
		print("[treinador] pesos guardados:", destino + ".json", flush=True)
	else:
		modelo.save(destino)
		print("[treinador] modelo guardado:", destino + ".zip", flush=True)


def treinar(env, nome_modelo, passos, pasta):
	"""Corre na thread de treino. Devolve o caminho do modelo guardado."""
	dispositivo = "cuda" if torch.cuda.is_available() else "cpu"
	print(f"[treinador] Dispositivo: {dispositivo.upper()}", flush=True)
	from stable_baselines3 import PPO, SAC
	from sb3_contrib import RecurrentPPO
	from stable_baselines3.common.monitor import Monitor

	modelos = {
		"ppo_mlp": (PPO, "MlpPolicy"),
		"ppo_lstm": (RecurrentPPO, "MlpLstmPolicy"),
		"sac_mlp": (SAC, "MlpPolicy"),
	}
	if nome_modelo not in modelos:
		raise ValueError("TREINO_MODELO tem de ser um de: %s" % ", ".join(modelos))
	cls, politica = modelos[nome_modelo]

	os.makedirs(os.path.join(pasta, "modelos"), exist_ok=True)
	os.makedirs(os.path.join(pasta, "logs"), exist_ok=True)
	env = Monitor(env, filename=os.path.join(pasta, "logs", nome_modelo + "_episodios.csv"))

	kwargs = {"verbose": 1, "seed": 42, "device": dispositivo}
	try:
		import tensorboard  # noqa: F401
		kwargs["tensorboard_log"] = os.path.join(pasta, "logs", "tensorboard")
	except ImportError:
		pass
	if nome_modelo == "sac_mlp":
		kwargs.update({"learning_starts": 1000, "buffer_size": 100_000})
	else:
		kwargs.update({"n_steps": 1024, "batch_size": 64})

	modelo = cls(politica, env, **kwargs)
	destino = os.path.join(pasta, "modelos", nome_modelo)
	continuar = os.environ.get("TREINO_CONTINUAR", "0") == "1"
	if continuar:
		if nome_modelo != "ppo_mlp":
			raise ValueError("TREINO_CONTINUAR só funciona com o ppo_mlp")
		if not os.path.isfile(destino + ".json"):
			raise FileNotFoundError("Não há %s.json para continuar" % destino)
		with open(destino + ".json", encoding="utf-8") as f:
			carregar_estado(modelo, json.load(f))
		print("[treinador] a continuar a partir de", destino + ".json", flush=True)

	# Backup do modelo antigo ANTES de começar: o guardado final vai escrever por cima do .json.
	if nome_modelo == "ppo_mlp" and not continuar and os.path.isfile(destino + ".json"):
		shutil.copyfile(destino + ".json", destino + ".anterior.json")   # não perder o modelo antigo

	from stable_baselines3.common.callbacks import BaseCallback

	class GuardarPorEpisodios(BaseCallback):
		"""Guarda o modelo de X em X episódios (tentativas), substituindo o ficheiro anterior."""

		def __init__(self, cada):
			super().__init__()
			self.cada = cada
			self.episodios = 0

		def _on_step(self):
			# 'dones' tem um True por cada ambiente cujo episódio acabou neste passo
			terminados = int(self.locals["dones"].sum())
			for _ in range(terminados):
				self.episodios += 1
				if self.episodios % self.cada == 0:
					try:
						_guardar(self.model, nome_modelo, destino)   # substitui o último guardado
						print("[treinador] episódio %d" % self.episodios, flush=True)
					except Exception:   # um erro a guardar não deve matar o treino
						traceback.print_exc()
			return True

	cada = int(os.environ.get("TREINO_GUARDAR_CADA_EPISODIOS", "100"))
	callback = GuardarPorEpisodios(cada) if cada > 0 else None
	try:
		modelo.learn(total_timesteps=passos, callback=callback, progress_bar=False)
	finally:
		_guardar(modelo, nome_modelo, destino)
	return destino


