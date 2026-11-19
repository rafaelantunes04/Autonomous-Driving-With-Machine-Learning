"""Ponte Godot/treino; nome mantido por compatibilidade com as cenas."""
import enum
import queue
import threading
import traceback
from py4godot.classes import gdclass
from py4godot.classes.Node import Node
from carro_treino_api import CarroTreinoAPI
from constantes import FRAMES_POR_ACAO, pasta_do_projeto

class Estado(enum.Enum):
	ESPERA = 0     # à espera de um comando do SB3
	CORRENDO = 1   # a deixar o carro andar FRAMES_POR_ACAO ticks


@gdclass
class treino_ppo(Node):
	"""Nó filho do carro: faz de simulador para o treino (thread de física do Godot)."""

	def _ready(self) -> None:
		from ambiente_interno import AmbienteInterno, TreinoInterrompido

		self.carro = CarroTreinoAPI(self.get_parent())
		self.q_cmd = queue.Queue()
		self.q_res = queue.Queue()
		self.parar = threading.Event()
		self.fim = threading.Event()
		self.estado = Estado.ESPERA
		self.frames = 0
		self.a_sair = False

		from treinador import ler_configuracao
		config = ler_configuracao()
		env = AmbienteInterno(self.q_cmd, self.q_res, self.parar)

		def correr():
			try:
				from treinador import treinar
				treinar(env, config, pasta_do_projeto())
			except TreinoInterrompido:
				print("[treino_ppo] interrompido", flush=True)
			except Exception:
				traceback.print_exc()
			finally:
				self.fim.set()

		print("[treino_ppo] a treinar %s durante %d passos..." % (config["modelo"], config["passos"]), flush=True)
		self.thread = threading.Thread(target=correr, daemon=True)
		self.thread.start()

	def _exit_tree(self) -> None:
		self.parar.set()

	def _physics_process(self, delta: float) -> None:
		if self.fim.is_set():
			self._fechar_jogo()
		elif self.estado == Estado.ESPERA:
			self._atender_comando()
		else:
			self._avancar_frames()

	def _fechar_jogo(self) -> None:
		if not self.a_sair:
			self.a_sair = True
			print("[treino_ppo] fim do treino, a fechar o jogo", flush=True)
			self.carro.sair()

	def _atender_comando(self) -> None:
		"""Recebe "reset" ou "step" do SB3. O reset responde logo; o step deixa o carro andar."""
		try:
			cmd = self.q_cmd.get_nowait()
		except queue.Empty:
			return
		if cmd[0] == "reset":
			self.carro.reiniciar(cmd[1])
			self.q_res.put(self.carro.resultado())
		else:   # "step"
			self.carro.comando(cmd[1][0], cmd[1][1])
			self.carro.congelar(False)
			self.frames = FRAMES_POR_ACAO
			self.estado = Estado.CORRENDO

	def _avancar_frames(self) -> None:
		"""Passados FRAMES_POR_ACAO ticks, congela o carro e devolve o resultado ao SB3."""
		self.frames -= 1
		if self.frames <= 0:
			self.carro.congelar(True)
			self.carro.avaliar()
			self.q_res.put(self.carro.resultado())
			self.estado = Estado.ESPERA
