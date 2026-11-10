"""Treina uma política no Godot e guarda o modelo e as métricas do treino."""

import argparse
from pathlib import Path

from stable_baselines3 import PPO, SAC
from sb3_contrib import RecurrentPPO
from stable_baselines3.common.monitor import Monitor
from rl.ambiente import AmbienteGodot

# Algoritmos fornecidos pelas bibliotecas. As referências explicam os métodos.
# PPO: https://arxiv.org/abs/1707.06347
# LSTM: https://doi.org/10.1162/neco.1997.9.8.1735
# RecurrentPPO: https://sb3-contrib.readthedocs.io/en/stable/modules/ppo_recurrent.html
# SAC: https://proceedings.mlr.press/v80/haarnoja18b.html
MODELOS = {
    "ppo_mlp": (PPO, "MlpPolicy"),
    "ppo_lstm": (RecurrentPPO, "MlpLstmPolicy"),
    "sac_mlp": (SAC, "MlpPolicy"),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--modelo", choices=MODELOS, required=True)
    parser.add_argument("--passos", type=int, default=100_000)
    parser.add_argument("--projeto", default=".")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--cena", default="res://cenas/track.tscn")
    parser.add_argument("--porta", type=int, default=8765)
    args = parser.parse_args()
    Path("modelos").mkdir(exist_ok=True)
    Path("logs").mkdir(exist_ok=True)
    cls, politica = MODELOS[args.modelo]
    # O ambiente troca ações e observações com o Godot. O Monitor regista cada episódio.
    env = Monitor(AmbienteGodot(args.projeto, args.godot, args.cena, args.porta), filename=f"logs/{args.modelo}_episodios.csv")
    try:
        kwargs = {"verbose": 1, "tensorboard_log": "logs/tensorboard", "seed": 42, "device": "cpu"}
        if args.modelo == "sac_mlp":
            kwargs.update({"learning_starts": 1000, "buffer_size": 100_000})
        else:
            kwargs.update({"n_steps": 1024, "batch_size": 64})
        modelo = cls(politica, env, **kwargs)
        try:
            # Cada passo corresponde a uma ação enviada ao simulador.
            modelo.learn(total_timesteps=args.passos, progress_bar=False)
        finally:
            # corrida_ppo.py carrega o PPO-MLP guardado aqui para pilotar.
            modelo.save(f"modelos/{args.modelo}")
            print(f"Modelo salvo: modelos/{args.modelo}.zip")
    finally:
        env.close()


if __name__ == "__main__":
    main()
