"""Guardar e carregar os pesos do PPO-MLP em JSON (e os outros modelos em .zip do SB3).

O JSON tem o ator ("camadas", é o que o corrida_ppo.py lê), o crítico e o log_std,
para o treino poder continuar mais tarde.
"""

import json
import os

import torch


def _camadas(sequencia, final):
	"""Lista de camadas [{w, b, ativacao}] de uma Sequential (Linear/Tanh) mais a camada final linear."""
	def linear(m, ativacao):
		return {
			"w": m.weight.detach().cpu().numpy().astype("float64").tolist(),   # (saida, entrada)
			"b": m.bias.detach().cpu().numpy().astype("float64").tolist(),
			"ativacao": ativacao,
		}

	camadas = []
	for m in sequencia:
		tipo = type(m).__name__
		if tipo == "Linear":
			camadas.append(linear(m, "linear"))
		elif tipo == "Tanh" and camadas:
			camadas[-1]["ativacao"] = "tanh"
		else:
			raise ValueError("Camada %s não suportada" % tipo)
	camadas.append(linear(final, "linear"))
	return camadas


def estado_ppo_mlp(modelo):
	"""Ator, crítico e log_std de um PPO-MLP do SB3."""
	pol = modelo.policy
	return {
		"camadas": _camadas(pol.mlp_extractor.policy_net, pol.action_net),
		"critico": _camadas(pol.mlp_extractor.value_net, pol.value_net),
		"log_std": pol.log_std.detach().cpu().numpy().astype("float64").tolist(),
	}


def _preencher(modulos, camadas, nome):
	"""Copia os pesos de `camadas` para a lista de módulos Linear."""
	if len(modulos) != len(camadas):
		raise ValueError("%s: o ficheiro tem %d camadas e o modelo %d" % (nome, len(camadas), len(modulos)))
	for m, c in zip(modulos, camadas):
		w = torch.tensor(c["w"], dtype=m.weight.dtype)
		if tuple(w.shape) != tuple(m.weight.shape):
			raise ValueError("%s: forma %s no ficheiro, %s no modelo" % (nome, tuple(w.shape), tuple(m.weight.shape)))
		with torch.no_grad():
			m.weight.copy_(w)
			m.bias.copy_(torch.tensor(c["b"], dtype=m.bias.dtype))


def carregar_estado(modelo, dados):
	"""Põe os pesos guardados num PPO-MLP novo (o inverso de estado_ppo_mlp)."""
	pol = modelo.policy
	linear = lambda seq: [m for m in seq if type(m).__name__ == "Linear"]
	_preencher(linear(pol.mlp_extractor.policy_net) + [pol.action_net], dados["camadas"], "ator")
	if "critico" in dados:
		_preencher(linear(pol.mlp_extractor.value_net) + [pol.value_net], dados["critico"], "crítico")
	else:
		print("[treino_ppo] o ficheiro só tem o ator: o crítico e o log_std começam de novo", flush=True)
	if "log_std" in dados:
		with torch.no_grad():
			pol.log_std.copy_(torch.tensor(dados["log_std"], dtype=pol.log_std.dtype))


def guardar(modelo, nome_modelo, destino):
	"""Escreve o modelo no disco (o ppo_mlp em JSON, os outros em .zip do SB3)."""
	if nome_modelo == "ppo_mlp":
		tmp = destino + ".json.tmp"
		with open(tmp, "w", encoding="utf-8") as f:
			json.dump(estado_ppo_mlp(modelo), f)
		os.replace(tmp, destino + ".json")   # troca atómica: nunca fica um JSON a meio
		print("[treino_ppo] pesos guardados:", destino + ".json", flush=True)
	else:
		modelo.save(destino)
		print("[treino_ppo] modelo guardado:", destino + ".zip", flush=True)


def carregar_json(destino):
	"""Lê o JSON de pesos de `destino` (sem extensão)."""
	caminho = destino + ".json"
	if not os.path.isfile(caminho):
		raise FileNotFoundError("Não há %s para continuar" % caminho)
	with open(caminho, encoding="utf-8") as f:
		return json.load(f)
