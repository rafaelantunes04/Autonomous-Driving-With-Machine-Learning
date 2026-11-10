"""Testa o PPO-MLP já treinado no Carro_1 durante cinco corridas no Godot.
O modelo só escolhe ações durante o teste. Os outros carros ficam parados.
"""
import argparse
from pathlib import Path
import numpy as np
from stable_baselines3 import PPO
from rl.cliente_godot import ClienteGodot


def main():
    parser = argparse.ArgumentParser()
    origem = parser.add_mutually_exclusive_group(required=True)
    origem.add_argument("--godot", help="Executável para abrir uma nova janela do Godot")
    origem.add_argument("--conectar", action="store_true", help="Usa o Godot já aberto pelo F5")
    parser.add_argument("--projeto", default=".")
    parser.add_argument("--cena", default="res://cenas/track.tscn")
    parser.add_argument("--porta", type=int, default=8765)
    parser.add_argument("--seed", type=int, default=10004)
    args = parser.parse_args()
    # Carrega os pesos guardados por treinar.py.
    arquivo = Path(args.projeto) / "modelos" / "ppo_mlp.zip"
    if not arquivo.is_file():
        raise SystemExit(f"Modelo nao encontrado: {arquivo}")
    modelo = PPO.load(str(arquivo), device="cpu")
    print("Corrida PPO-MLP: 5 voltas, HUD ativo. Carro_1 e controlado pela IA.", flush=True)
    cliente = ClienteGodot(args.projeto, args.godot, args.cena, args.porta, "race")
    try:
        # O Godot abre a pista seguinte quando o jogador clica em Continuar.
        for corrida in range(1, 6):
            if corrida == 1:
                resp = cliente.comando("reset", seed=args.seed, corrida=1)
            else:
                print("Aguardando o botão para iniciar a corrida %d..." % corrida, flush=True)
                resp = cliente.comando(
                    "aguardar_proxima_corrida",
                    tempo_limite=None,
                    corrida=corrida - 1
                )

            # Lê o estado do carro e devolve a ação escolhida pelo modelo.
            while not resp["dones"][0]:
                obs = np.asarray(resp["observations"][0], dtype=np.float32)
                acao, _ = modelo.predict(obs, deterministic=True)
                resp = cliente.comando(
                    "step",
                    actions=[np.asarray(acao, dtype=float).reshape(-1).tolist()]
                )
                info = resp["infos"][0]
                passos = info["passos"]
                if passos % 150 == 0:
                    print(
                        f"Tempo simulado ~{passos*4/60:.0f}s | "
                        f"batidas: {info['batidas']} | "
                        f"progresso: {info['progresso']:.0f} px",
                        flush=True
                    )

            info = resp["infos"][0]
            print("\nRESULTADO CORRIDA %d/5:" % corrida, info, flush=True)
            if info["motivo"] == "vitoria":
                print("O PPO completou as 5 voltas!", flush=True)
            else:
                print("O PPO nao concluiu as 5 voltas nesta corrida.", flush=True)

        if args.conectar:
            # O botão Fechar Teste do Godot encerra a ligação.
            cliente.aguardar_fecho()
        else:
            try:
                input("Pressione Enter para fechar o Godot...")
            except EOFError:
                pass
    except ConnectionError:
        if not args.conectar:
            raise
    finally:
        cliente.close()


if __name__ == "__main__":
    main()
