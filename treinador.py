"""Gestão de treino comum a PPO, SAC e RecurrentPPO, sem dependência do Godot."""
import os
import shutil
import traceback
import torch
from modelos_io import carregar_estado, carregar_json, guardar

def ler_configuracao():
	"""Lê as variáveis de ambiente TREINO_*."""
	return {
		"modelo": os.environ.get("TREINO_MODELO", "ppo_mlp"),
		"passos": int(os.environ.get("TREINO_PASSOS", "100000")),
		"continuar": os.environ.get("TREINO_CONTINUAR", "0") == "1",
		"guardar_cada": int(os.environ.get("TREINO_GUARDAR_CADA_EPISODIOS", "100")),
	}


def _escolher_dispositivo(nome_modelo):
	if nome_modelo == "ppo_mlp":
		return "cpu"
	return "cuda" if torch.cuda.is_available() else "cpu"

def _criar_modelo(env, nome_modelo, pasta):
	"""Cria o modelo SB3 escolhido, com o Monitor e (se houver) o tensorboard."""

	from stable_baselines3 import PPO, SAC
	from stable_baselines3.common.monitor import Monitor
	from sb3_contrib import RecurrentPPO

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

	dispositivo = _escolher_dispositivo(nome_modelo)
	print("[treinador] Dispositivo:", dispositivo.upper(), flush=True)
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
	return cls(politica, env, **kwargs)


def _preparar_ficheiro(modelo, nome_modelo, destino, continuar):
	"""Continua a partir do JSON guardado, ou faz backup do modelo antigo antes de treinar do zero."""
	if continuar:
		if nome_modelo != "ppo_mlp":
			raise ValueError("TREINO_CONTINUAR só funciona com o ppo_mlp")
		carregar_estado(modelo, carregar_json(destino))
		print("[treinador] a continuar a partir de", destino + ".json", flush=True)
	elif nome_modelo == "ppo_mlp" and os.path.isfile(destino + ".json"):
		shutil.copyfile(destino + ".json", destino + ".anterior.json")   # o guardado final escreve por cima


def _criar_callback(nome_modelo, destino, cada):
	"""Callback do SB3 que guarda o modelo de `cada` em `cada` episódios."""
	from stable_baselines3.common.callbacks import BaseCallback

	class GuardarPorEpisodios(BaseCallback):
		def __init__(self):
			super().__init__()
			self.episodios = 0

		def _on_step(self):
			for _ in range(int(self.locals["dones"].sum())):   # um True por episódio acabado
				self.episodios += 1
				if self.episodios % cada == 0:
					try:
						guardar(self.model, nome_modelo, destino)
						print("[treinador] episódio %d" % self.episodios, flush=True)
					except Exception:   # um erro a guardar não deve matar o treino
						traceback.print_exc()
			return True

	return GuardarPorEpisodios()


def treinar(env, config, pasta):
	"""Corre na thread de treino."""
	nome = config["modelo"]
	modelo = _criar_modelo(env, nome, pasta)
	destino = os.path.join(pasta, "modelos", nome)
	_preparar_ficheiro(modelo, nome, destino, config["continuar"])

	callback = _criar_callback(nome, destino, config["guardar_cada"]) if config["guardar_cada"] > 0 else None
	try:
		modelo.learn(total_timesteps=config["passos"], callback=callback, progress_bar=False)
	finally:
		try:
			guardar(modelo, nome, destino)
		finally:
			modelo.get_env().close()


