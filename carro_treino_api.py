"""Extensão da CarroAPI só para o treino por reforço (ver scripts/rl/treino_rl.gd)."""

from carro_api import CarroAPI

# Tem de seguir a ordem do enum TreinoRL.Motivo
MOTIVOS = ("", "batida", "volta", "tempo")


class CarroTreinoAPI(CarroAPI):
	"""CarroAPI com os comandos e resultados do treino."""

	def reiniciar(self, seed):
		"""Pista nova e carro na partida, parado e congelado até ao primeiro passo."""
		self._escrever("rl_reset", int(seed))

	def congelar(self, congelado):
		"""True pára a física do carro (entre ações); False deixa-a correr."""
		self._escrever("rl_congelado", bool(congelado))

	def avaliar(self):
		"""Fecha um passo: calcula a recompensa e se o episódio acabou."""
		self._escrever("rl_avaliar", True)

	def sair(self):
		"""Fecha o jogo."""
		self._escrever("rl_sair", True)

	def resultado(self):
		"""Observação, recompensa e estado do episódio, num dicionário simples."""
		motivo = int(self._ler("rl_motivo"))
		return {
			"obs": self.observacao,
			"recompensa": self._ler("rl_recompensa"),
			"terminado": bool(self._ler("rl_terminado")),
			"motivo": MOTIVOS[motivo] if 0 <= motivo < len(MOTIVOS) else "",
		}
