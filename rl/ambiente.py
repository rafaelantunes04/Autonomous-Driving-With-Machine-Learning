"""Adapta a PonteRL do Godot à interface de treino do Gymnasium."""
import numpy as np
import gymnasium as gym
from gymnasium import spaces
from .cliente_godot import ClienteGodot


class AmbienteGodot(gym.Env):
    metadata = {"render_modes": []}

    def __init__(self, projeto: str, godot: str, cena: str, porta: int = 8765):
        super().__init__()
        self.cliente = ClienteGodot(projeto, godot, cena, porta, "train")
        # Duas ações: acelerador/travão e direção. A ponte calcula as oito observações.
        self.action_space = spaces.Box(-1.0, 1.0, shape=(2,), dtype=np.float32)
        self.observation_space = spaces.Box(
            low=np.array([-1, -3, -1, -1, -1, -1, -1, 0], dtype=np.float32),
            high=np.array([1, 3, 1, 1, 1, 1, 1, 1], dtype=np.float32),
            dtype=np.float32,
        )
        self.episodio = 0

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        # Envia uma seed ao Godot. Track decide se a usa ou sorteia outra.
        s = int(seed) if seed is not None else int(self.np_random.integers(1, 2**30))
        resp = self.cliente.comando("reset", seed=s)
        self.episodio += 1
        return np.asarray(resp["observations"][0], dtype=np.float32), resp["infos"][0]

    def step(self, action):
        # Aplica uma ação e devolve a observação, a recompensa e o fim do episódio.
        acao = np.clip(np.asarray(action, dtype=np.float32), -1, 1).tolist()
        resp = self.cliente.comando("step", actions=[acao])
        obs = np.asarray(resp["observations"][0], dtype=np.float32)
        info = resp["infos"][0]
        terminou = bool(resp["dones"][0]) and info["motivo"] != "tempo"
        truncado = bool(resp["dones"][0]) and info["motivo"] == "tempo"
        return obs, float(resp["rewards"][0]), terminou, truncado, info

    def close(self):
        if hasattr(self, "cliente"):
            self.cliente.close()
