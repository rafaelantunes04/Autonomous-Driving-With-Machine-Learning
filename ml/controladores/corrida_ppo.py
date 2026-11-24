"""Controlador Python que conduz o carro com o modelo PPO treinado (via py4godot).

Sem torch nem stable-baselines3: os pesos vêm de
ml/pesos/ppo_mlp.json (escrito pelo treino, godot --headless --path . -- --treino) e a rede
(MLP 7 -> 64 -> 64 -> 2, tanh) é calculada aqui em Python puro.

As 7 observações (velocidade, ângulo das rodas e 5 raycasts) são calculadas no Godot (scripts/rl/observacao_rl.gd) e lidas
com CarroAPI.observacao. Tal como no treino, o modelo escolhe uma ação a cada
4 ticks de física e mantém-na entre escolhas.

IMPORTANTE: o nome da classe tem de ser igual ao nome do ficheiro
(corrida_ppo.py -> class corrida_ppo).
"""

import json
import math
import os
import sys
from pathlib import Path
try:
    _RAIZ = str(Path(__file__).resolve().parents[2])
except NameError:
    _RAIZ = os.getcwd()
if _RAIZ not in sys.path:
    sys.path.insert(0, _RAIZ)

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from ml.ambiente.carro_api import CarroAPI
from ml.constantes import FICHEIRO_PESOS, FRAMES_POR_ACAO, OBSERVACOES, pasta_ml

INTERVALO_PRINT = 1.0


def _procurar_pesos():
	"""Caminho do JSON de pesos, ou None se ainda não houver treino."""
	caminho = os.path.join(pasta_ml(), FICHEIRO_PESOS)
	return caminho if os.path.isfile(caminho) else None


def _carregar_rede(caminho):
	with open(caminho, encoding="utf-8") as f:
		return json.load(f)["camadas"]


from ml.modelos.ppo_modelo import prever as _prever


@gdclass
class corrida_ppo(Node):
	"""Nó que o Godot anexa ao carro e que o comanda a cada tick de física."""

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
			print("[corrida_ppo] não encontrei %s. Treina primeiro (godot --headless --path . -- --treino)" % FICHEIRO_PESOS)
			return
		rede = _carregar_rede(caminho)
		entradas = len(rede[0]["w"][0])
		if entradas != OBSERVACOES:
			print("[corrida_ppo] %s espera %d observações e o carro dá %d: é de um modelo antigo. Treina de novo." % (caminho, entradas, OBSERVACOES))
			return
		self.rede = rede
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
