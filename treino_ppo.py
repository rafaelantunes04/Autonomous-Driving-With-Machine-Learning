"""Ligação entre a física do Godot e o ambiente de treino.

O nome histórico é mantido porque a cena o carrega via py4godot.
Serve PPO, SAC e PPO-LSTM; a gestão dos treinos está em treinador.py.
A classe tem de ter o mesmo nome do ficheiro.
"""

import os
import queue
import threading
import traceback
from py4godot.classes import gdclass
from py4godot.classes.Node import Node
from carro_api import CarroAPI

FRAMES_POR_ACAO = 4  # Igual a TreinoRL.FRAMES_POR_ACAO
ESPERA, CORRENDO = 0, 1

def _pasta_projeto():
	"""Pasta do projeto: junto a este script, ou a pasta de trabalho do Godot."""
	candidatas = []
	try:
		candidatas.append(os.path.dirname(os.path.abspath(__file__)))
	except NameError:
		pass
	candidatas.append(os.getcwd())
	for pasta in candidatas:
		if os.path.isfile(os.path.join(pasta, "project.godot")):
			return pasta
	return candidatas[0]


@gdclass
class treino_ppo(Node):
	"""Nó filho do carro: faz de simulador para o treino (thread de física do Godot)."""

	nome_modelo = "Treino"

	def _ready(self) -> None:
		from ambiente_interno import AmbienteInterno, TreinoInterrompido

		self.carro = CarroAPI(self.get_parent())
		self.q_cmd = queue.Queue()
		self.q_res = queue.Queue()
		self.parar = threading.Event()
		self.fim = threading.Event()
		self.estado = ESPERA
		self.frames = 0
		self.a_sair = False

		nome = os.environ.get("TREINO_MODELO", "ppo_mlp")
		passos = int(os.environ.get("TREINO_PASSOS", "100000"))
		env = AmbienteInterno(self.q_cmd, self.q_res, self.parar)

		def correr():
			try:
				from treinador import treinar
				treinar(env, nome, passos, _pasta_projeto())
			except TreinoInterrompido:
				print("[treino_ppo] interrompido", flush=True)
			except Exception:
				traceback.print_exc()
			finally:
				self.fim.set()

		print("[treino_ppo] a treinar %s durante %d passos..." % (nome, passos), flush=True)
		self.thread = threading.Thread(target=correr, daemon=True)
		self.thread.start()

	def _exit_tree(self) -> None:
		self.parar.set()

	def _physics_process(self, delta: float) -> None:
		if self.fim.is_set():
			if not self.a_sair:
				self.a_sair = True
				print("[treino_ppo] fim do treino, a fechar o jogo", flush=True)
				self.carro.rl_sair()
			return

		if self.estado == ESPERA:
			try:
				cmd = self.q_cmd.get_nowait()
			except queue.Empty:
				return
			if cmd[0] == "reset":
				self.carro.rl_reiniciar(cmd[1])
				self.q_res.put(self.carro.rl_resultado())
			else:   # "step"
				self.carro.comando(cmd[1][0], cmd[1][1])
				self.carro.rl_congelar(False)
				self.frames = FRAMES_POR_ACAO
				self.estado = CORRENDO
		else:
			self.frames -= 1
			if self.frames <= 0:
				self.carro.rl_congelar(True)
				self.carro.rl_avaliar()
				self.q_res.put(self.carro.rl_resultado())
				self.estado = ESPERA