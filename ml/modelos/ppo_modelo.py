"""Pesos PPO: exportação e reposição; não inclui o estado do otimizador."""

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
	import torch
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
	import torch
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



def pesos_ppo_mlp(modelo):
	"""Exporta apenas o ator PPO."""
	return _camadas(modelo.policy.mlp_extractor.policy_net, modelo.policy.action_net)


def prever(camadas, observacao):
    """Ator determinístico PPO-MLP, com clipping igual ao predict() do SB3."""
    import math
    x = list(observacao)
    if not all(math.isfinite(v) for v in x):
        raise ValueError("Observação PPO inválida")
    for camada in camadas:
        if len(camada["w"]) != len(camada["b"]) or any(len(w) != len(x) for w in camada["w"]):
            raise ValueError("Dimensões PPO incompatíveis")
        x = [sum(w * v for w, v in zip(linha, x)) + b for linha, b in zip(camada["w"], camada["b"])]
        if camada["ativacao"] == "tanh":
            x = [math.tanh(v) for v in x]
        elif camada["ativacao"] != "linear":
            raise ValueError("Ativação PPO não suportada")
    return [max(-1.0, min(1.0, v)) for v in x]
