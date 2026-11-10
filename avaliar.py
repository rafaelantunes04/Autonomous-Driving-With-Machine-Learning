"""Compara três políticas já treinadas, na mesma pista em cada ensaio.

Requer os três modelos guardados pelo treinar.py. Exporta resultados em CSV.
"""
import argparse
import csv
from pathlib import Path
import numpy as np
from stable_baselines3 import PPO, SAC
from sb3_contrib import RecurrentPPO
from rl.cliente_godot import ClienteGodot


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--projeto", default=".")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--cena", default="res://cenas/track.tscn")
    parser.add_argument("--porta", type=int, default=8765)
    parser.add_argument("--seeds", type=int, nargs="+", default=[10001, 10002, 10003, 10004, 10005])
    args = parser.parse_args()

    arquivos = [("ppo_mlp", PPO), ("ppo_lstm", RecurrentPPO), ("sac_mlp", SAC)]
    modelos = []
    for nome, classe in arquivos:
        path = Path(f"modelos/{nome}.zip")
        if not path.is_file():
            raise FileNotFoundError(f"Treine primeiro: {path}")
        modelos.append(classe.load(str(path), device="cpu"))

    Path("resultados").mkdir(exist_ok=True)
    cliente = ClienteGodot(args.projeto, args.godot, args.cena, args.porta, "eval")
    linhas = []
    try:
        for seed in args.seeds:
            resp = cliente.comando("reset", seed=seed)
            estados = [None, None, None]
            inicios = np.ones((3,), dtype=bool)
            for _ in range(1600):
                acoes = []
                for i, modelo in enumerate(modelos):
                    if resp["dones"][i]:
                        acoes.append([0.0, 0.0])
                        continue
                    obs = np.asarray(resp["observations"][i], dtype=np.float32)
                    if i == 1:
                        acao, estados[i] = modelo.predict(obs, state=estados[i], episode_start=np.array([inicios[i]]), deterministic=True)
                    else:
                        acao, _ = modelo.predict(obs, deterministic=True)
                    acoes.append(np.asarray(acao).reshape(-1).tolist())
                    inicios[i] = False
                resp = cliente.comando("step", actions=acoes)
                if all(resp["dones"]):
                    break
            for i, (nome, _) in enumerate(arquivos):
                info = resp["infos"][i]
                linhas.append({"seed": seed, "modelo": nome, "motivo": info["motivo"], "progresso_px": round(info["progresso"], 2), "comprimento_px": round(info["comprimento"], 2), "colisoes": info["batidas"], "passos": info["passos"]})
                print(seed, nome, info)
    finally:
        cliente.close()

    with open("resultados/avaliacao.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=linhas[0].keys())
        w.writeheader()
        w.writerows(linhas)
    print("Resultados salvos em resultados/avaliacao.csv")


if __name__ == "__main__":
    main()
