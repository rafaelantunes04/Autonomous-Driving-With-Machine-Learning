"""Treina uma política dentro do Godot, via py4godot (sem TCP).

Usa a cena cenas/treino.tscn (Corrida com modo_treino ligado). O SB3 corre
numa thread própria; este nó, na thread de física do Godot, serve-lhe de
simulador: recebe ações por uma fila, deixa o carro andar FRAMES_POR_ACAO ticks
e devolve observação e recompensa por outra fila. As regras (recompensa, fim de
episódio) estão em scripts/rl/treino_rl.gd.

Escolhe-se o modelo e a duração com variáveis de ambiente:
    TREINO_MODELO = ppo_mlp (por omissão) | ppo_lstm | sac_mlp
    TREINO_PASSOS = 100000 (por omissão)
    TREINO_CONTINUAR = 1 para continuar a partir de modelos/ppo_mlp.json (por omissão 0 = do zero)
    TREINO_GUARDAR_CADA_EPISODIOS = 100 (por omissão): guarda o modelo de X em X
                          episódios, por cima do anterior (0 = só guarda no fim)

Só o ppo_mlp é guardado em JSON (modelos/ppo_mlp.json, o que o corrida_ppo.py lê);
o ppo_lstm e o sac_mlp ficam em modelos/<modelo>.zip do SB3. No fim fecha o jogo.

IMPORTANTE: o nome da classe tem de ser igual ao nome do ficheiro.
"""

import enum
import os
import queue
import shutil
import threading
import traceback
import torch
import torch
from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_treino_api import CarroTreinoAPI
from constantes import FRAMES_POR_ACAO, pasta_do_projeto
from modelos_io import carregar_estado, carregar_json, guardar

DISPOSITIVO = ""



class Estado(enum.Enum):
	ESPERA = 0     # à espera de um comando do SB3
	CORRENDO = 1   # a deixar o carro andar FRAMES_POR_ACAO ticks


def _ler_configuracao():
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

	DISPOSITIVO = _escolher_dispositivo(nome_modelo)
	kwargs = {"verbose": 1, "seed": 42, "device": DISPOSITIVO}
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
		print("[treino_ppo] a continuar a partir de", destino + ".json", flush=True)
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
						print("[treino_ppo] episódio %d" % self.episodios, flush=True)
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
		guardar(modelo, nome, destino)


@gdclass
class treino_ppo(Node):
	"""Nó filho do carro: faz de simulador para o treino (thread de física do Godot)."""

	def _ready(self) -> None:
		from ambiente_interno import AmbienteInterno, TreinoInterrompido

		print("[treino_ppo] a utilizar o dispositivo:", DISPOSITIVO.upper(), flush=True)
		print("[DEBUG] Torch path:", torch.__file__, "| Version:", torch.__version__, flush=True)
		self.carro = CarroTreinoAPI(self.get_parent())
		self.q_cmd = queue.Queue()
		self.q_res = queue.Queue()
		self.parar = threading.Event()
		self.fim = threading.Event()
		self.estado = Estado.ESPERA
		self.frames = 0
		self.a_sair = False

		config = _ler_configuracao()
		env = AmbienteInterno(self.q_cmd, self.q_res, self.parar)

		def correr():
			try:
				treinar(env, config, pasta_do_projeto())
			except TreinoInterrompido:
				print("[treino_ppo] interrompido", flush=True)
			except Exception:
				traceback.print_exc()
			finally:
				self.fim.set()

		print("[treino_ppo] a treinar %s durante %d passos..." % (config["modelo"], config["passos"]), flush=True)
		self.thread = threading.Thread(target=correr, daemon=True)
		self.thread.start()

	def _exit_tree(self) -> None:
		self.parar.set()

	def _physics_process(self, delta: float) -> None:
		if self.fim.is_set():
			self._fechar_jogo()
		elif self.estado == Estado.ESPERA:
			self._atender_comando()
		else:
			self._avancar_frames()

	def _fechar_jogo(self) -> None:
		if not self.a_sair:
			self.a_sair = True
			print("[treino_ppo] fim do treino, a fechar o jogo", flush=True)
			self.carro.sair()

	def _atender_comando(self) -> None:
		"""Recebe "reset" ou "step" do SB3. O reset responde logo; o step deixa o carro andar."""
		try:
			cmd = self.q_cmd.get_nowait()
		except queue.Empty:
			return
		if cmd[0] == "reset":
			self.carro.reiniciar(cmd[1])
			self.q_res.put(self.carro.resultado())
		else:   # "step"
			self.carro.comando(cmd[1][0], cmd[1][1])
			self.carro.congelar(False)
			self.frames = FRAMES_POR_ACAO
			self.estado = Estado.CORRENDO

	def _avancar_frames(self) -> None:
		"""Passados FRAMES_POR_ACAO ticks, congela o carro e devolve o resultado ao SB3."""
		self.frames -= 1
		if self.frames <= 0:
			self.carro.congelar(True)
			self.carro.avaliar()
			self.q_res.put(self.carro.resultado())
			self.estado = Estado.ESPERA
