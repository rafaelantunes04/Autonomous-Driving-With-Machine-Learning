"""Treina uma política dentro do Godot, via py4godot (sem TCP).

Usa a cena cenas/treino.tscn (Corrida com modo_treino ligado). O SB3 corre
numa thread própria; este nó, na thread de física do Godot, serve-lhe de
simulador: recebe ações por uma fila, deixa o carro andar 4 ticks e devolve
observação e recompensa por outra fila. As regras (recompensa, fim de episódio)
estão em scripts/rl/treino_rl.gd.

Escolhe-se o modelo e a duração com variáveis de ambiente:
    TREINO_MODELO = ppo_mlp (por omissão) | ppo_lstm | sac_mlp
    TREINO_PASSOS = 100000 (por omissão)
    TREINO_CONTINUAR = 1 para continuar a partir de modelos/ppo_mlp.json (por omissão 0 = do zero)
    TREINO_GUARDAR_CADA_EPISODIOS = 100 (por omissão): guarda o modelo de X em X episódios
                          (tentativas) durante o treino, substituindo sempre o ficheiro anterior
                          (0 = só guarda no fim)

Guarda os pesos em modelos/<modelo>.json (é o que o corrida_ppo.py lê) durante o
treino (de X em X episódios, sempre por cima do anterior) e no fim, e fecha o jogo. Só o ppo_mlp tem este formato; o ppo_lstm e o sac_mlp, que não
cabem num JSON simples, são guardados como modelos/<modelo>.zip do SB3.

IMPORTANTE: o nome da classe tem de ser igual ao nome do ficheiro.
"""

import json
import os
import queue
import shutil
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


def _camadas(sequencia, final):
	"""Lista de camadas [{w, b, ativacao}] de uma Sequential (Linear/Tanh) mais a camada final linear."""
	def linear(m, ativacao):
		return {
			"w": m.weight.detach().cpu().numpy().astype("float64").tolist(),   # (saida, entrada)
			"b": m.bias.detach().cpu().numpy().astype("float64").tolist(),
			"ativacao": ativacao,
		}

	camadas = []
	for m in sequencia:
		tipo = type(m).__name__
		if tipo == "Linear":
			camadas.append(linear(m, "linear"))
		elif tipo == "Tanh" and camadas:
			camadas[-1]["ativacao"] = "tanh"
		else:
			raise ValueError("Camada %s não suportada" % tipo)
	camadas.append(linear(final, "linear"))
	return camadas


def pesos_ppo_mlp(modelo):
	"""Pesos do ator de um PPO-MLP do SB3 (é o que o corrida_ppo.py usa)."""
	return _camadas(modelo.policy.mlp_extractor.policy_net, modelo.policy.action_net)


def estado_ppo_mlp(modelo):
	"""Tudo o que é preciso para continuar o treino: ator, crítico e log_std.

	O corrida_ppo.py só lê "camadas"; o resto é ignorado a conduzir.
	"""
	pol = modelo.policy
	return {
		"camadas": _camadas(pol.mlp_extractor.policy_net, pol.action_net),
		"critico": _camadas(pol.mlp_extractor.value_net, pol.value_net),
		"log_std": pol.log_std.detach().cpu().numpy().astype("float64").tolist(),
	}


def carregar_estado(modelo, dados):
	"""Põe os pesos guardados num PPO-MLP novo (o inverso de estado_ppo_mlp)."""
	import torch

	def preencher(modulos, camadas, nome):
		if len(modulos) != len(camadas):
			raise ValueError("%s: o ficheiro tem %d camadas e o modelo %d" % (nome, len(camadas), len(modulos)))
		for m, c in zip(modulos, camadas):
			w = torch.tensor(c["w"], dtype=m.weight.dtype)
			if tuple(w.shape) != tuple(m.weight.shape):
				raise ValueError("%s: forma %s no ficheiro, %s no modelo" % (nome, tuple(w.shape), tuple(m.weight.shape)))
			with torch.no_grad():
				m.weight.copy_(w)
				m.bias.copy_(torch.tensor(c["b"], dtype=m.bias.dtype))

	pol = modelo.policy
	linear = lambda seq: [m for m in seq if type(m).__name__ == "Linear"]
	preencher(linear(pol.mlp_extractor.policy_net) + [pol.action_net], dados["camadas"], "ator")
	if "critico" in dados:
		preencher(linear(pol.mlp_extractor.value_net) + [pol.value_net], dados["critico"], "crítico")
	else:
		print("[treino_ppo] o ficheiro só tem o ator: o crítico e o log_std começam de novo", flush=True)
	if "log_std" in dados:
		with torch.no_grad():
			pol.log_std.copy_(torch.tensor(dados["log_std"], dtype=pol.log_std.dtype))


def _guardar(modelo, nome_modelo, destino):
	"""Escreve o modelo no disco (o ppo_mlp em JSON, os outros em .zip do SB3)."""
	if nome_modelo == "ppo_mlp":
		tmp = destino + ".json.tmp"
		with open(tmp, "w", encoding="utf-8") as f:
			json.dump(estado_ppo_mlp(modelo), f)
		os.replace(tmp, destino + ".json")   # troca atómica: nunca fica um JSON a meio
		print("[treino_ppo] pesos guardados:", destino + ".json", flush=True)
	else:
		modelo.save(destino)
		print("[treino_ppo] modelo guardado:", destino + ".zip", flush=True)


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
	continuar = os.environ.get("TREINO_CONTINUAR", "0") == "1"
	if continuar:
		if nome_modelo != "ppo_mlp":
			raise ValueError("TREINO_CONTINUAR só funciona com o ppo_mlp")
		if not os.path.isfile(destino + ".json"):
			raise FileNotFoundError("Não há %s.json para continuar" % destino)
		with open(destino + ".json", encoding="utf-8") as f:
			carregar_estado(modelo, json.load(f))
		print("[treino_ppo] a continuar a partir de", destino + ".json", flush=True)

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
						print("[treino_ppo] episódio %d" % self.episodios, flush=True)
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