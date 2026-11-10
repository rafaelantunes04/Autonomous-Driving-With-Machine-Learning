"""Teste da ponte, sem treinar uma rede neural."""
import argparse
from rl.ambiente import AmbienteGodot

p = argparse.ArgumentParser()
p.add_argument("--godot", default="godot")
p.add_argument("--projeto", default=".")
p.add_argument("--cena", default="res://cenas/track.tscn")
p.add_argument("--porta", type=int, default=8765)
a = p.parse_args()
amb = AmbienteGodot(a.projeto, a.godot, a.cena, a.porta)
try:
    obs, info = amb.reset(seed=123)
    print("RESET:", obs, info)
    for k in range(10):
        obs, reward, done, truncated, info = amb.step([1.0, 0.1])
        print(k, obs.round(3), round(reward, 3), done, truncated)
        if done or truncated:
            break
finally:
    amb.close()
