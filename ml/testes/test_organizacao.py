import json
import pathlib
import queue
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
import gymnasium as gym
import numpy as np
import torch
from stable_baselines3 import PPO
from sb3_contrib import RecurrentPPO
from ml.modelos.modelos_io import guardar, carregar_json
from ml.modelos.ppo_modelo import prever
from ml.treino.treinador import treinar
from ml.avaliacao.avaliacao import Politica, avaliar, carregar_seeds
from ml.ambiente.ambiente_interno import AmbienteInterno

torch.set_num_threads(1)


class Ambiente(gym.Env):
    observation_space = gym.spaces.Box(-1, 1, (7,), dtype=np.float32)
    action_space = gym.spaces.Box(-1, 1, (2,), dtype=np.float32)

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        self.seed_episodio = seed
        self.passos = 0
        return np.zeros(7, dtype=np.float32), {}

    def step(self, action):
        self.passos += 1
        fim = self.passos >= 4
        return np.zeros(7, dtype=np.float32), -float(np.square(action).sum()), fim, False, {
            "seed": self.seed_episodio, "is_success": False, "motivo": "batida" if fim else "",
            "batidas": int(fim), "progresso_fracao": .2, "tempo_simulado_s": self.passos * 4 / 60}


def criar_ppo(env, nome, pasta, seed):
    return PPO("MlpPolicy", env, n_steps=8, batch_size=4, n_epochs=1, seed=seed, device="cpu")


class Organizacao(unittest.TestCase):
    def test_ppo_exportacao_e_retoma_sem_perder_logs(self):
        with tempfile.TemporaryDirectory() as folder, patch("ml.treino.treinador._criar_modelo", side_effect=criar_ppo):
            config = dict(modelo="ppo_mlp", passos=8, continuar=False, seed=42, guardar_cada=1)
            primeira = pathlib.Path(treinar(Ambiente(), config, folder))
            config["continuar"] = True
            segunda = pathlib.Path(treinar(Ambiente(), config, folder))
            self.assertNotEqual(primeira, segunda)
            self.assertTrue((primeira / "modelos/ppo_mlp.zip").exists())
            model = PPO.load(str(pathlib.Path(folder) / "ml/pesos/ppo_mlp.zip"), device="cpu")
            self.assertEqual(model.num_timesteps, 16)
            data = carregar_json(str(pathlib.Path(folder) / "ml/pesos/ppo_mlp"))
            for obs in np.random.default_rng(7).uniform(-1, 1, (30, 7)).astype(np.float32):
                np.testing.assert_allclose(prever(data["camadas"], obs), model.predict(obs, deterministic=True)[0], atol=1e-6)
            self.assertEqual(json.loads((segunda / "configuracao.json").read_text())["estado"], "concluido")

    def test_lstm_reset_memoria_e_checkpoint(self):
        model = RecurrentPPO("MlpLstmPolicy", Ambiente(), n_steps=8, batch_size=4, n_epochs=1,
            policy_kwargs=dict(lstm_hidden_size=16, net_arch=dict(pi=[16], vf=[16])), seed=42, device="cpu")
        model.learn(8)
        with tempfile.TemporaryDirectory() as folder:
            path = str(pathlib.Path(folder) / "ppo_lstm")
            guardar(model, "ppo_lstm", path)
            politica = Politica("ppo_lstm", path + ".zip")
            obs = np.ones(7, dtype=np.float32)
            inicial = politica.prever(obs)
            for _ in range(3):
                politica.prever(-obs)
            politica.reiniciar()
            np.testing.assert_allclose(politica.prever(obs), inicial, atol=1e-7)
            restored = RecurrentPPO.load(path, env=Ambiente(), device="cpu")
            restored.learn(8, reset_num_timesteps=False)
            self.assertEqual(restored.num_timesteps, 16)

    def test_avaliacao_exporta_falhas_sem_inventar_tempo_conclusao(self):
        with tempfile.TemporaryDirectory() as folder:
            base = pathlib.Path(folder)
            guardar(PPO("MlpPolicy", Ambiente(), n_steps=8, batch_size=4, device="cpu"), "ppo_mlp", str(base / "ml/pesos/ppo_mlp"))
            saida = pathlib.Path(avaliar(Ambiente(), base, seeds=[1500000001, 1500000002], nomes=("ppo_mlp",)))
            resumo = json.loads((saida / "resumo.json").read_text())["ppo_mlp"]
            self.assertEqual(resumo["episodios"], 2)
            self.assertEqual(resumo["taxa_colisao"], 1)
            self.assertEqual(resumo["taxa_conclusao"], 0)
            self.assertIsNone(resumo["tempo_medio_concluidos_s"])
            self.assertEqual(len((saida / "episodios.csv").read_text().splitlines()), 3)

    def test_separacao_das_seeds(self):
        validacao = carregar_seeds(ROOT, "validacao")
        teste = carregar_seeds(ROOT, "teste")
        self.assertFalse(set(validacao) & set(teste))
        env = AmbienteInterno(queue.Queue(), queue.Queue(), threading.Event())
        with self.assertRaises(ValueError):
            env.reset(seed=validacao[0])

    def test_csv_do_colega_regista_episodios(self):
        import csv
        from stable_baselines3.common.monitor import Monitor
        from ml.treino.treinador import _criar_callback_csv
        with tempfile.TemporaryDirectory() as folder:
            caminho = pathlib.Path(folder) / "episodios.csv"
            env = Monitor(Ambiente(), info_keywords=("seed", "is_success", "motivo"))
            modelo = criar_ppo(env, "ppo_mlp", folder, 42)
            modelo.learn(8, callback=_criar_callback_csv(str(caminho)))
            with caminho.open(encoding="utf-8", newline="") as f:
                linhas = list(csv.DictReader(f))
            self.assertEqual(len(linhas), 2)
            self.assertEqual([r["episodio"] for r in linhas], ["1", "2"])
            self.assertEqual(linhas[-1]["passos"], "8")
            self.assertEqual(linhas[-1]["motivo"], "batida")
            env.close()

    def test_estrutura_ml_e_referencias_godot(self):
        import re
        from ml.constantes import pasta_do_projeto, pasta_pesos
        from ml.treino.experiencias import proveniencia
        self.assertEqual(pathlib.Path(pasta_do_projeto()), ROOT)
        self.assertEqual(pathlib.Path(pasta_pesos()), ROOT / "ml/pesos")
        fontes = proveniencia(ROOT)["fontes_sha256"]
        self.assertIn("ml/treino/treinador.py", fontes)
        for f in [*(ROOT / "cenas").glob("*.tscn"), ROOT / "scripts/corrida/corrida.gd"]:
            for caminho in re.findall(r'res://([^"\n]+\.(?:py|gd|tscn))', f.read_text()):
                self.assertTrue((ROOT / caminho).is_file(), caminho)

    def test_cenas_explicitas(self):
        for nome, algoritmo in (("ppo", "ppo_mlp"), ("sac", "sac_mlp"), ("ppo_lstm", "ppo_lstm")):
            texto = (ROOT / "cenas" / ("treino_" + nome + ".tscn")).read_text()
            self.assertIn("modo_treino = true", texto)
            self.assertIn('modelo_treino = "' + algoritmo + '"', texto)
        texto = (ROOT / "cenas/comparacao.tscn").read_text()
        self.assertIn("demonstrar_ppo_lstm = true", texto)


if __name__ == "__main__":
    unittest.main()
