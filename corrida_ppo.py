"""Controlador Python que conduz o carro com o modelo PPO treinado (via py4godot).

Sem torch nem stable-baselines3: os pesos vêm de
modelos/ppo_mlp.json (escrito pelo treino, cenas/treino.tscn) e a rede
(MLP 8 -> 64 -> 64 -> 2, tanh) é calculada aqui em Python puro.

As 8 observações são calculadas no Godot (scripts/rl/observacao_rl.gd) e lidas
com CarroAPI.observacao. Tal como no treino, o modelo escolhe uma ação a cada
4 ticks de física e mantém-na entre escolhas.

IMPORTANTE: o nome da classe tem de ser igual ao nome do ficheiro
(corrida_ppo.py -> class corrida_ppo).
"""

import json
import math
import os

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_api import CarroAPI

FICHEIRO_PESOS = os.path.join("modelos", "ppo_mlp.json")
FRAMES_POR_ACAO = 4   # igual ao treino
INTERVALO_PRINT = 1.0


def _procurar_pesos():
	"""Procura o JSON junto a este script e na pasta de trabalho do Godot."""
	bases = []
	try:
		bases.append(os.path.dirname(os.path.abspath(__file__)))
	except NameError:
		pass
	bases.append(os.getcwd())
	for base in bases:
		caminho = os.path.join(base, FICHEIRO_PESOS)
		if os.path.isfile(caminho):
			return caminho
	return None


def _carregar_rede(caminho):
	with open(caminho, encoding="utf-8") as f:
		return json.load(f)["camadas"]


def _prever(camadas, obs):
	"""Passagem direta da rede: devolve [acelerar, virar] em [-1, 1] (política determinística)."""
	x = obs
	for camada in camadas:
		x = [sum(w * v for w, v in zip(linha, x)) + b for linha, b in zip(camada["w"], camada["b"])]
		if camada["ativacao"] == "tanh":
			x = [math.tanh(v) for v in x]
	return [max(-1.0, min(1.0, v)) for v in x]


@gdclass
class corrida_ppo(Node):
	"""Nó que o Godot anexa ao carro e que o comanda a cada tick de física."""

	# O HUD mostra este texto ao lado do nome do carro
	nome_modelo = "PPO-MLP"

	def _ready(self) -> None:
		"""Liga-se ao carro (o nó pai) e carrega a rede."""
		self.carro = CarroAPI(self.get_parent())
		self.tempo = 0.0
		self.proximo_print = 0.0
		self.frames = 0
		self.acao = [0.0, 0.0]
		self.rede = None

		caminho = _procurar_pesos()
		if caminho is None:
			print("[corrida_ppo] não encontrei %s. Treina primeiro (cenas/treino.tscn)" % FICHEIRO_PESOS)
			return
		self.rede = _carregar_rede(caminho)
		print("[corrida_ppo] pronto, pesos em", caminho)

	def _physics_process(self, delta: float) -> None:
		"""A cada FRAMES_POR_ACAO ticks lê as observações e escolhe uma nova ação."""
		if self.rede is None:
			return
		self.tempo += delta

		if self.frames % FRAMES_POR_ACAO == 0:
			self.acao = _prever(self.rede, self.carro.observacao)
		self.frames += 1

		if self.acao[0] >= 0:
			self.carro.acelerar(self.acao[0])
		else:
			self.carro.recuar(-self.acao[0])
		self.carro.virar(self.acao[1])

		if self.tempo >= self.proximo_print:
			self.proximo_print += INTERVALO_PRINT
			print("[corrida_ppo] velocidade=%.0f km/h | acel=%.2f | volante=%.2f" % (
				self.carro.velocidade, self.acao[0], self.acao[1]))
