"""Controlador Godot para PPO com memória LSTM."""

import os
import sys
from pathlib import Path
try:
    _RAIZ = str(Path(__file__).resolve().parents[2])
except NameError:
    _RAIZ = os.getcwd()
if _RAIZ not in sys.path:
    sys.path.insert(0, _RAIZ)

import numpy as np
from sb3_contrib import RecurrentPPO
from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from ml.ambiente.carro_api import CarroAPI
from ml.constantes import (
	FRAMES_POR_ACAO,
	OBSERVACOES,
	pasta_ml,
)


@gdclass
class corrida_ppo_lstm(Node):
	def _ready(self) -> None:
		self.carro = CarroAPI(self.get_parent())
		self.modelo = None

		self.memoria = None
		self.inicio_episodio = np.array([True], dtype=bool)
		self.episodio = -1

		self.frames = 0
		self.acao = [0.0, 0.0]

		caminho = os.path.join(
			pasta_ml(),
			"pesos",
			"ppo_lstm.zip",
		)

		if not os.path.isfile(caminho):
			print(
                "[PPO-LSTM] Falta ml/pesos/ppo_lstm.zip. "
				"Treina o modelo primeiro.",
				flush=True,
			)
			self.carro.parar()
			return

		# A condução pode usar CPU mesmo que o treino tenha usado GPU.
		modelo = RecurrentPPO.load(caminho, device="cpu")

		if modelo.observation_space.shape != (OBSERVACOES,):
			raise ValueError("Observações incompatíveis com o carro")

		if (
			modelo.action_space.shape != (2,)
			or not np.allclose(modelo.action_space.low, -1.0)
			or not np.allclose(modelo.action_space.high, 1.0)
		):
			raise ValueError("Ações incompatíveis com o carro")

		self.modelo = modelo
		print("[PPO-LSTM] Modelo carregado:", caminho, flush=True)

	def _physics_process(self, delta: float) -> None:
		if self.modelo is None:
			return

		episodio_atual = int(
			self.get_parent().get("episodio_id")
		)

		# Cada reinício do carro começa com memória limpa.
		if episodio_atual != self.episodio:
			self.episodio = episodio_atual
			self.memoria = None
			self.inicio_episodio[:] = True
			self.frames = 0
			self.acao = [0.0, 0.0]

		# Atualiza a memória apenas quando escolhe uma nova ação,
		# respeitando o mesmo intervalo usado no treino.
		if self.frames % FRAMES_POR_ACAO == 0:
			observacao = np.asarray(
				self.carro.observacao,
				dtype=np.float32,
			)

			acao, self.memoria = self.modelo.predict(
				observacao,
				state=self.memoria,
				episode_start=self.inicio_episodio,
				deterministic=True,
			)

			self.inicio_episodio[:] = False
			self.acao = np.asarray(acao).reshape(2).tolist()

		self.carro.comando(*self.acao)
		self.frames += 1
