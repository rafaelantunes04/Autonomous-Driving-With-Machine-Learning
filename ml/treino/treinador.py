"""Gestão de treino comum a PPO, SAC e RecurrentPPO, sem dependência do Godot."""
import csv
import os
import shutil
import time
import traceback
import torch
from ml.constantes import pasta_logs, pasta_pesos
from ml.modelos.modelos_io import carregar_estado, carregar_json, guardar

def ler_configuracao():
	"""Lê as variáveis de ambiente TREINO_*."""
	return {
		"modelo": os.environ.get("TREINO_MODELO", "ppo_mlp"),
		"passos": int(os.environ.get("TREINO_PASSOS", "100000")),
		"continuar": os.environ.get("TREINO_CONTINUAR", "0") == "1",
		"seed": int(os.environ.get("TREINO_SEED", "42")),
		"guardar_cada": int(os.environ.get("TREINO_GUARDAR_CADA_EPISODIOS", "100")),
	}


def _escolher_dispositivo(nome_modelo):
	opcao = os.environ.get("TREINO_DISPOSITIVO", "auto")
	if opcao not in ("auto", "cpu", "cuda"):
		raise ValueError("TREINO_DISPOSITIVO deve ser auto, cpu ou cuda")
	if opcao != "auto":
		return opcao
	if nome_modelo == "ppo_mlp":
		return "cpu"
	return "cuda" if torch.cuda.is_available() else "cpu"

def _criar_modelo(env, nome_modelo, pasta, seed=42):
	"""Cria o modelo SB3 escolhido, com o Monitor e (se houver) o tensorboard."""

	from stable_baselines3 import PPO, SAC
	from stable_baselines3.common.monitor import Monitor
	if nome_modelo == "ppo_lstm":
		from sb3_contrib import RecurrentPPO

	modelos = {
		"ppo_mlp": (PPO, "MlpPolicy"),

		"sac_mlp": (SAC, "MlpPolicy"),
	}
	if nome_modelo == "ppo_lstm":
		modelos["ppo_lstm"] = (RecurrentPPO, "MlpLstmPolicy")
	if nome_modelo not in modelos:
		raise ValueError("TREINO_MODELO tem de ser um de: %s" % ", ".join(modelos))
	cls, politica = modelos[nome_modelo]

	os.makedirs(pasta_pesos(pasta), exist_ok=True)
	os.makedirs(pasta_logs(pasta), exist_ok=True)
	# Sem ficheiro: o Monitor só junta as estatísticas do episódio ao `info`; o CSV é escrito por _criar_callback_csv.
	env = Monitor(env, filename=None, info_keywords=("seed", "is_success", "motivo"))

	dispositivo = _escolher_dispositivo(nome_modelo)
	print("[treinador] Dispositivo:", dispositivo.upper(), flush=True)
	kwargs = {"verbose": 1, "seed": seed, "device": dispositivo}
	try:
		import tensorboard  # noqa: F401
		kwargs["tensorboard_log"] = os.path.join(pasta_logs(pasta), "tensorboard")
	except ImportError:
		pass
	if nome_modelo == "sac_mlp":
		kwargs.update({"learning_starts": 1000, "buffer_size": 100_000, "batch_size": 256, "learning_rate": 3e-4, "train_freq": 1, "gradient_steps": 1, "gamma": 0.99, "tau": 0.005, "ent_coef": "auto", "policy_kwargs": {"net_arch": [256, 256]}})
	else:
		kwargs.update({"n_steps": 1024, "batch_size": 64})
	return cls(politica, env, **kwargs)


def _preparar_ficheiro(modelo, nome_modelo, destino, continuar):
	"""Continua a partir do JSON guardado, ou faz backup do modelo antigo antes de treinar do zero."""
	if nome_modelo == "sac_mlp":
		if continuar:
			from stable_baselines3 import SAC
			for ext in (".zip", ".replay.pkl"):
				if not os.path.isfile(destino + ext):
					raise FileNotFoundError("Falta ficheiro para retomar SAC: " + destino + ext)
			novo = SAC.load(destino + ".zip", env=modelo.get_env(), device=modelo.device)
			novo.load_replay_buffer(destino + ".replay.pkl")
			print("[SAC] Retomado aos", novo.num_timesteps, "passos", flush=True)
			return novo
		for ext in (".zip", ".replay.pkl", ".json"):
			if os.path.isfile(destino + ext):
				shutil.copyfile(destino + ext, destino + ".anterior" + ext)
		return modelo
	if continuar:
		if nome_modelo != "ppo_mlp":
			raise ValueError("TREINO_CONTINUAR só funciona com o ppo_mlp")
		carregar_estado(modelo, carregar_json(destino))
		print("[treinador] a continuar a partir de", destino + ".json", flush=True)
	elif nome_modelo == "ppo_mlp" and os.path.isfile(destino + ".json"):
		shutil.copyfile(destino + ".json", destino + ".anterior.json")   # o guardado final escreve por cima

	return modelo


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


COLUNAS_CSV = ("episodio", "data_hora", "passos", "recompensa", "duracao_passos", "tempo_s", "seed", "sucesso", "motivo")


def _criar_callback_csv(caminho):
	"""Callback do SB3 que acrescenta uma linha por episódio a `caminho` (CSV simples de estatísticas do treino)."""
	from stable_baselines3.common.callbacks import BaseCallback

	class EstatisticasCSV(BaseCallback):
		def __init__(self):
			super().__init__()
			self.episodio = 0
			if os.path.isfile(caminho):   # retoma: continua a numeração
				with open(caminho, encoding="utf-8") as f:
					self.episodio = max(0, sum(1 for _ in f) - 1)

		def _on_step(self):
			for info in self.locals.get("infos", ()):
				ep = info.get("episode")
				if ep is None:
					continue
				self.episodio += 1
				novo = not os.path.isfile(caminho)
				try:
					with open(caminho, "a", newline="", encoding="utf-8") as f:
						w = csv.writer(f)
						if novo:
							w.writerow(COLUNAS_CSV)
						w.writerow([
							self.episodio, time.strftime("%Y-%m-%d %H:%M:%S"), self.num_timesteps,
							round(float(ep["r"]), 4), int(ep["l"]), round(float(ep["t"]), 2),
							ep.get("seed", ""), ep.get("is_success", ""), ep.get("motivo", ""),
						])
				except Exception:   # um erro a escrever o CSV não deve matar o treino
					traceback.print_exc()
			return True

	return EstatisticasCSV()


def treinar(env, config, pasta):
	"""Corre na thread de treino. `pasta` é a pasta de saída: contém pesos/ e logs/ (por omissão, ml/)."""
	pasta = os.environ.get("TREINO_PASTA_SAIDA", pasta)
	nome = config["modelo"]
	modelo = _criar_modelo(env, nome, pasta, config.get("seed", 42))
	destino = os.path.join(pasta_pesos(pasta), nome)
	try:
		modelo = _preparar_ficheiro(modelo, nome, destino, config["continuar"])
	except Exception:
		modelo.get_env().close()
		raise

	# Um CSV por modelo (logs/<modelo>.csv). Treinar de novo guarda o anterior como .anterior.csv; continuar acrescenta.
	csv_estatisticas = os.path.join(pasta_logs(pasta), nome + ".csv")
	if not config["continuar"] and os.path.isfile(csv_estatisticas):
		shutil.move(csv_estatisticas, os.path.join(pasta_logs(pasta), nome + ".anterior.csv"))
	callbacks = [_criar_callback_csv(csv_estatisticas)]
	if config["guardar_cada"] > 0:
		callbacks.append(_criar_callback(nome, destino, config["guardar_cada"]))
	callback = callbacks
	try:
		modelo.learn(total_timesteps=config["passos"], callback=callback, progress_bar=False, reset_num_timesteps=not (config["continuar"] and nome == "sac_mlp"))
	finally:
		try:
			guardar(modelo, nome, destino)
		finally:
			modelo.get_env().close()


