"""Treina uma política dentro do Godot, via py4godot (sem TCP).

Usa a cena cenas/treino.tscn (Corrida com modo_treino ligado). O SB3 corre
numa thread própria; este nó, na thread de física do Godot, serve-lhe de
simulador: recebe ações por uma fila, deixa o carro andar 4 ticks e devolve
observação e recompensa por outra fila. As regras (recompensa, fim de episódio)
estão em scripts/rl/treino_rl.gd.

Escolhe-se o modelo e a duração com variáveis de ambiente:
    TREINO_MODELO = ppo_mlp (por omissão) | ppo_lstm | sac_mlp
    TREINO_PASSOS = 100000 (por omissão)

No fim guarda os pesos em modelos/<modelo>.json (é o que o corrida_ppo.py lê)
e fecha o jogo. Só o ppo_mlp tem este formato; o ppo_lstm e o sac_mlp, que não
cabem num JSON simples, são guardados como modelos/<modelo>.zip do SB3.

IMPORTANTE: o nome da classe tem de ser igual ao nome do ficheiro.
"""

import json
import os
import queue
import threading
import traceback

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_api import CarroAPI

FRAMES_POR_ACAO = 4   # tem de ser igual a TreinoRL.FRAMES_POR_ACAO
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


def pesos_ppo_mlp(modelo):
	"""Pesos do ator de um PPO-MLP do SB3, como lista de camadas [{w, b, ativacao}].

	Percorre policy_net (Linear + Tanh, ...) e depois o action_net (linear).
	"""
	def linear(m, ativacao):
		return {
			"w": m.weight.detach().cpu().numpy().astype("float64").tolist(),   # (saida, entrada)
			"b": m.bias.detach().cpu().numpy().astype("float64").tolist(),
			"ativacao": ativacao,
		}

	camadas = []
	for m in modelo.policy.mlp_extractor.policy_net:
		tipo = type(m).__name__
		if tipo == "Linear":
			camadas.append(linear(m, "linear"))
		elif tipo == "Tanh" and camadas:
			camadas[-1]["ativacao"] = "tanh"
		else:
			raise ValueError("Camada %s não suportada pelo corrida_ppo.py" % tipo)
	camadas.append(linear(modelo.policy.action_net, "linear"))
	return camadas


def treinar(env, nome_modelo, passos, pasta):
	"""Corre na thread de treino. Devolve o caminho do modelo guardado."""
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

	kwargs = {"verbose": 1, "seed": 42, "device": "cpu"}
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
	try:
		modelo.learn(total_timesteps=passos, progress_bar=False)
	finally:
		if nome_modelo == "ppo_mlp":
			with open(destino + ".json", "w", encoding="utf-8") as f:
				json.dump({"camadas": pesos_ppo_mlp(modelo)}, f)
			print("[treino_ppo] pesos guardados:", destino + ".json", flush=True)
		else:
			modelo.save(destino)
			print("[treino_ppo] modelo guardado:", destino + ".zip", flush=True)
	return destino


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
