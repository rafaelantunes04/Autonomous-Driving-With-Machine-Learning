"""Ator SAC determinístico exportável, sem dependências na inferência."""
import math

def exportar(modelo):
	ator = modelo.policy.actor
	camadas = []
	for m in ator.latent_pi:
		tipo = type(m).__name__
		if tipo == "Linear":
			camadas.append({"w": m.weight.detach().cpu().tolist(), "b": m.bias.detach().cpu().tolist(), "ativacao": "linear"})
		elif tipo == "ReLU":
			camadas[-1]["ativacao"] = "relu"
		else:
			raise ValueError("Camada SAC não suportada: " + tipo)
	m = ator.mu
	camadas.append({"w": m.weight.detach().cpu().tolist(), "b": m.bias.detach().cpu().tolist(), "ativacao": "tanh"})
	return {"algoritmo": "SAC", "camadas": camadas, "low": modelo.action_space.low.tolist(), "high": modelo.action_space.high.tolist(), "observacoes": int(modelo.observation_space.shape[0])}

def prever(rede, obs):
	if len(obs) != rede["observacoes"] or not all(math.isfinite(v) for v in obs):
		raise ValueError("Observação SAC inválida")
	x = list(obs)
	for c in rede["camadas"]:
		if len(c["w"]) != len(c["b"]) or any(len(w) != len(x) for w in c["w"]):
			raise ValueError("Dimensões inválidas na rede SAC")
		x = [sum(w*v for w,v in zip(row,x))+b for row,b in zip(c["w"],c["b"])]
		if c["ativacao"] == "relu": x = [max(0.,v) for v in x]
		elif c["ativacao"] == "tanh": x = [math.tanh(v) for v in x]
		elif c["ativacao"] != "linear": raise ValueError("Ativação inválida")
	if len(x) != len(rede["low"]) or not all(math.isfinite(v) for v in x):
		raise ValueError("Ação SAC inválida")
	return [lo+(v+1)*0.5*(hi-lo) for v,lo,hi in zip(x,rede["low"],rede["high"])]
