"""Exportação e reposição de pesos PPO-MLP, independentes do Godot."""

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


def pesos_ppo_mlp(modelo):
	"""Pesos do ator de um PPO-MLP do SB3 (é o que o corrida_ppo.py usa)."""
	return _camadas(modelo.policy.mlp_extractor.policy_net, modelo.policy.action_net)


def estado_ppo_mlp(modelo):
	"""Pesos do ator, crítico e log_std; não inclui o estado do otimizador.

	O corrida_ppo.py só lê "camadas"; o resto é ignorado a conduzir.
	"""
	pol = modelo.policy
	return {
		"camadas": _camadas(pol.mlp_extractor.policy_net, pol.action_net),
		"critico": _camadas(pol.mlp_extractor.value_net, pol.value_net),
		"log_std": pol.log_std.detach().cpu().numpy().astype("float64").tolist(),
	}


def carregar_estado(modelo, dados):
	"""Põe os pesos guardados num PPO-MLP novo (o inverso de estado_ppo_mlp)."""
	import torch

	def preencher(modulos, camadas, nome):
		if len(modulos) != len(camadas):
			raise ValueError("%s: o ficheiro tem %d camadas e o modelo %d" % (nome, len(camadas), len(modulos)))
		for m, c in zip(modulos, camadas):
			w = torch.tensor(c["w"], dtype=m.weight.dtype)
			if tuple(w.shape) != tuple(m.weight.shape):
				raise ValueError("%s: forma %s no ficheiro, %s no modelo" % (nome, tuple(w.shape), tuple(m.weight.shape)))
			with torch.no_grad():
				m.weight.copy_(w)
				m.bias.copy_(torch.tensor(c["b"], dtype=m.bias.dtype))

	pol = modelo.policy
	linear = lambda seq: [m for m in seq if type(m).__name__ == "Linear"]
	preencher(linear(pol.mlp_extractor.policy_net) + [pol.action_net], dados["camadas"], "ator")
	if "critico" in dados:
		preencher(linear(pol.mlp_extractor.value_net) + [pol.value_net], dados["critico"], "crítico")
	else:
		print("[treino_ppo] o ficheiro só tem o ator: o crítico e o log_std começam de novo", flush=True)
	if "log_std" in dados:
		with torch.no_grad():
			pol.log_std.copy_(torch.tensor(dados["log_std"], dtype=pol.log_std.dtype))


