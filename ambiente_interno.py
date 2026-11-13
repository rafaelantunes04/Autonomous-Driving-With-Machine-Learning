"""Ambiente Gymnasium que fala com o Godot sem TCP.

Corre na thread de treino. Em vez de sockets, troca mensagens com o nó
treino_ppo.py (que corre na thread de física do Godot) através de duas filas.
Não importa nada do Godot, por isso também pode ser testado à parte.
"""

import queue

import numpy as np
import gymnasium as gym
from gymnasium import spaces


class TreinoInterrompido(Exception):
	"""O jogo fechou enquanto o treino esperava por uma resposta."""


class AmbienteInterno(gym.Env):
	metadata = {"render_modes": []}

	def __init__(self, q_cmd: "queue.Queue", q_res: "queue.Queue", parar):
		super().__init__()
		self.q_cmd, self.q_res, self.parar = q_cmd, q_res, parar
		# Duas ações: acelerador/travão e direção. O Godot calcula as oito observações.
		self.action_space = spaces.Box(-1.0, 1.0, shape=(2,), dtype=np.float32)
		self.observation_space = spaces.Box(
			low=np.array([-1, -3, -1, -1, -1, -1, -1, 0], dtype=np.float32),
			high=np.array([1, 3, 1, 1, 1, 1, 1, 1], dtype=np.float32),
			dtype=np.float32,
		)

	def _pedir(self, *cmd):
		self.q_cmd.put(cmd)
		while True:
			if self.parar.is_set():
				raise TreinoInterrompido()
			try:
				return self.q_res.get(timeout=0.5)
			except queue.Empty:
				pass

	def reset(self, *, seed=None, options=None):
		super().reset(seed=seed)
		s = int(seed) if seed is not None else int(self.np_random.integers(1, 2**30))
		res = self._pedir("reset", s)
		return np.asarray(res["obs"], dtype=np.float32), res

	def step(self, action):
		acao = np.clip(np.asarray(action, dtype=np.float32), -1, 1).reshape(-1).tolist()
		res = self._pedir("step", acao)
		obs = np.asarray(res["obs"], dtype=np.float32)
		truncado = res["terminado"] and res["motivo"] == "tempo"
		terminou = res["terminado"] and not truncado
		return obs, float(res["recompensa"]), bool(terminou), bool(truncado), res
