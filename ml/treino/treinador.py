"""Gestão de treino PPO, SAC e PPO-LSTM, independente do Godot."""

import csv
import os
import shutil
import traceback

import torch

from ml.modelos.modelos_io import carregar_estado, carregar_json, guardar, publicar
from ml.treino.experiencias import nova_execucao, proveniencia, escrever_json, sha256
from pathlib import Path
import time


def ler_configuracao():
	"""Lê as opções de treino definidas pela ponte com o Godot."""
	return {
		"modelo": os.environ.get("TREINO_MODELO", "ppo_mlp"),
		"passos": int(os.environ.get("TREINO_PASSOS", "100000")),
		"continuar": os.environ.get("TREINO_CONTINUAR", "0") == "1",
		"seed": int(os.environ.get("TREINO_SEED", "42")),
		"guardar_cada": int(
			os.environ.get("TREINO_GUARDAR_CADA_EPISODIOS", "100")
		),
	}


def _escolher_dispositivo(nome_modelo):
	opcao = os.environ.get("TREINO_DISPOSITIVO", "auto")

	if opcao not in ("auto", "cpu", "cuda"):
		raise ValueError(
            "TREINO_DISPOSITIVO deve ser auto, cpu ou cuda"
		)

	if opcao != "auto":
		return opcao

	if nome_modelo == "ppo_mlp":
		return "cpu"

	return "cuda" if torch.cuda.is_available() else "cpu"


def _criar_modelo(env, nome_modelo, pasta, seed=42):
	"""Cria o algoritmo e configura as respetivas redes."""
	from stable_baselines3 import PPO, SAC
	from stable_baselines3.common.monitor import Monitor

	modelos = {
		"ppo_mlp": (PPO, "MlpPolicy"),
		"sac_mlp": (SAC, "MlpPolicy"),
	}

	if nome_modelo == "ppo_lstm":
		from sb3_contrib import RecurrentPPO

		modelos["ppo_lstm"] = (
			RecurrentPPO,
			"MlpLstmPolicy",
		)

	if nome_modelo not in modelos:
		raise ValueError(
            "Modelo inválido: escolhe ppo_mlp, sac_mlp ou ppo_lstm"
		)

	cls, politica = modelos[nome_modelo]
	dispositivo = _escolher_dispositivo(nome_modelo)

	os.makedirs(os.path.join(pasta, "modelos"), exist_ok=True)
	os.makedirs(os.path.join(pasta, "logs"), exist_ok=True)

	env = Monitor(
		env,
		filename=None,
		info_keywords=("seed", "is_success", "motivo"),
	)

	print(
		f"[treinador] Modelo: {nome_modelo} | "
		f"Dispositivo: {dispositivo.upper()}",
		flush=True,
	)

	kwargs = {
		"verbose": 1,
		"seed": seed,
		"device": dispositivo,
	}

	try:
		import tensorboard  # noqa: F401

		kwargs["tensorboard_log"] = os.path.join(
			pasta, "logs", "tensorboard"
		)
	except ImportError:
		pass

	if nome_modelo == "sac_mlp":
		kwargs.update({
			"learning_starts": 1000,
			"buffer_size": 100_000,
			"batch_size": 256,
			"learning_rate": 3e-4,
			"train_freq": 1,
			"gradient_steps": 1,
			"gamma": 0.99,
			"tau": 0.005,
			"ent_coef": "auto",
			"policy_kwargs": {
				"net_arch": [256, 256],
			},
		})

	elif nome_modelo == "ppo_lstm":
		kwargs.update({
			"learning_rate": 3e-4,
			"n_steps": 1024,
			"batch_size": 64,
			"n_epochs": 10,
			"gamma": 0.99,
			"gae_lambda": 0.95,
			"clip_range": 0.2,
			"policy_kwargs": {
				"lstm_hidden_size": 128,
				"n_lstm_layers": 1,
				"shared_lstm": False,
				"enable_critic_lstm": True,
				"net_arch": {
					"pi": [64, 64],
					"vf": [64, 64],
				},
			},
		})

	else:
		# PPO com MLP: mantém a configuração existente.
		kwargs.update({
			"n_steps": 1024,
			"batch_size": 64,
		})

	try:
		return cls(politica, env, **kwargs)
	except Exception:
		env.close()
		raise


def _fazer_backup(destino, extensoes):
	"""Preserva a versão anterior antes de começar do zero."""
	for extensao in extensoes:
		origem = destino + extensao

		if os.path.isfile(origem):
			shutil.copyfile(
				origem,
				destino + ".anterior" + extensao,
			)


def _preparar_ficheiro(modelo, nome_modelo, destino, continuar):
	"""Carrega um treino anterior ou preserva os ficheiros existentes."""
	if nome_modelo == "sac_mlp":
		if continuar:
			from stable_baselines3 import SAC

			for extensao in (".zip", ".replay.pkl"):
				if not os.path.isfile(destino + extensao):
					raise FileNotFoundError(
                        "Falta ficheiro para retomar SAC: "
						+ destino + extensao
					)

			novo = SAC.load(
				destino + ".zip",
				env=modelo.get_env(),
				device=modelo.device,
			)
			novo.load_replay_buffer(destino + ".replay.pkl")

			print(
				"[SAC] Retomado aos",
				novo.num_timesteps,
				"passos",
				flush=True,
			)
			return novo

		_fazer_backup(destino, (".zip", ".replay.pkl", ".json"))
		return modelo

	if nome_modelo == "ppo_lstm":
		if continuar:
			from sb3_contrib import RecurrentPPO

			caminho = destino + ".zip"

			if not os.path.isfile(caminho):
				raise FileNotFoundError(
                    "Falta ficheiro para retomar PPO-LSTM: "
					+ caminho
				)

			novo = RecurrentPPO.load(
				caminho,
				env=modelo.get_env(),
				device=modelo.device,
			)

			print(
				"[PPO-LSTM] Retomado aos",
				novo.num_timesteps,
				"passos",
				flush=True,
			)
			return novo

		_fazer_backup(destino, (".zip",))
		return modelo

	if nome_modelo == "ppo_mlp":
		if continuar:
			if os.path.isfile(destino + ".zip"):
				from stable_baselines3 import PPO
				return PPO.load(destino + ".zip", env=modelo.get_env(), device=modelo.device)
			carregar_estado(modelo, carregar_json(destino))
			print("[PPO] Retoma legada: apenas pesos JSON, sem otimizador/contador.", flush=True)
		else:
			_fazer_backup(destino, (".zip", ".json"))
		return modelo

	raise ValueError("Modelo não suportado: " + nome_modelo)


def _criar_callback(nome_modelo, destino, cada, destino_publicado=None):
	"""Guarda o modelo a cada número definido de episódios."""
	from stable_baselines3.common.callbacks import BaseCallback

	class GuardarPorEpisodios(BaseCallback):
		def __init__(self):
			super().__init__()
			self.episodios = 0

		def _on_step(self):
			terminados = int(self.locals["dones"].sum())

			for _ in range(terminados):
				self.episodios += 1

				if self.episodios % cada == 0:
					try:
						guardar(self.model, nome_modelo, destino)
						if destino_publicado is not None:
							publicar(destino, destino_publicado, nome_modelo)
						print(
							"[treinador] Episódio",
							self.episodios,
							flush=True,
						)
					except Exception:
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
	"""Cada chamada cria uma execução própria; retomar nunca apaga os registos anteriores."""
	if config["passos"] <= 0 or config["guardar_cada"] < 0:
		raise ValueError("Passos deve ser positivo e intervalo de gravação não negativo")
	# As pistas reservadas estão fora do intervalo usado pelo treino aleatório.
	if not 0 <= config.get("seed", 42) < 2**30:
		raise ValueError("Seed de treino deve estar no intervalo [0, 2**30)")
	projeto = Path(pasta)
	base = Path(os.environ.get("TREINO_PASTA_SAIDA", str(projeto)))
	nome = config["modelo"]
	execucao = nova_execucao(base / "experiencias", nome)
	destino = str(execucao / "modelos" / nome)
	atual = str(base / "ml" / "pesos" / nome)
	meta = proveniencia(projeto)
	meta.update({"configuracao": config, "estado": "a_preparar", "pasta": str(execucao)})
	origem = {}
	if config["continuar"]:
		for ext in (".zip", ".json", ".replay.pkl"):
			if Path(atual + ext).is_file():
				origem[ext] = sha256(atual + ext)
	meta["origem_sha256"] = origem
	escrever_json(execucao / "configuracao.json", meta)
	print("[treinador] Execução:", execucao, flush=True)
	modelo = None
	pronto = False
	inicio = time.perf_counter()
	try:
		(execucao / "logs").mkdir(exist_ok=True)
		modelo = _criar_modelo(env, nome, str(execucao), config.get("seed", 42))
		modelo = _preparar_ficheiro(modelo, nome, atual, config["continuar"])
		pronto = True
		meta["estado"] = "a_treinar"
		meta["dispositivo"] = str(modelo.device)
		meta["passos_iniciais"] = modelo.num_timesteps
		meta["parametros"] = {k: getattr(modelo, k, None) for k in (
			"n_steps", "batch_size", "n_epochs", "gamma", "gae_lambda", "learning_starts",
			"buffer_size", "gradient_steps", "tau", "ent_coef", "vf_coef")}
		# Algumas opções SAC, como ent_coef, podem ser tensores após load().
		meta["parametros"] = {k: v if isinstance(v, (str, int, float, bool, type(None))) else str(v)
							  for k, v in meta["parametros"].items()}
		meta["arquitetura"] = str(modelo.policy)
		escrever_json(execucao / "configuracao.json", meta)
		callback = [_criar_callback_csv(str(execucao / "logs" / "episodios.csv"))]
		if config["guardar_cada"]:
			callback.append(_criar_callback(nome, destino, config["guardar_cada"], atual))
		completo = config["continuar"] and bool(origem.get(".zip"))
		modelo.learn(total_timesteps=config["passos"], callback=callback, progress_bar=False,
					 reset_num_timesteps=not completo)
		meta["estado"] = "concluido"
	except BaseException as erro:
		meta["estado"] = "interrompido" if type(erro).__name__ in ("TreinoInterrompido", "KeyboardInterrupt") else "erro"
		meta["erro"] = str(erro) or type(erro).__name__
		raise
	finally:
		try:
			if pronto:
				guardar(modelo, nome, destino)
				publicar(destino, atual, nome)
				meta["passos_finais"] = modelo.num_timesteps
		except BaseException as erro_gravacao:
			meta["estado"] = "erro_gravacao"
			meta["erro_gravacao"] = str(erro_gravacao)
			raise
		finally:
			if modelo is not None:
				modelo.get_env().close()
			meta["tempo_real_segundos"] = time.perf_counter() - inicio
			escrever_json(execucao / "configuracao.json", meta)
	return str(execucao)
