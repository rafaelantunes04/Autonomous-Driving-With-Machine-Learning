"""Controlador Python do carro com interface Tkinter segura (via py4godot)."""

import threading
import tkinter as tk
from tkinter import ttk

from py4godot.classes import gdclass
from py4godot.classes.Node import Node

from carro_api import CarroAPI

# Instantes (em segundos) do programa de demonstração
FIM_ACELERAR = 1.0
FIM_RECUAR = 3.5
INTERVALO_PRINT = 1.0


@gdclass
class main(Node):
	"""Nó que o Godot anexa ao carro e que o comanda a cada tick de física."""

	def _ready(self) -> None:
		"""Chamado uma vez quando o nó entra na cena: liga-se ao carro e abre a UI."""
		self.carro = CarroAPI(self.get_parent())
		self.tempo = 0.0
		self.proximo_print = 0.0

		# Sistema de cache thread-safe para partilhar dados com o Tkinter
		self.lock = threading.Lock()
		self.cache_vel = 0.0
		self.cache_rumo = 0.0
		self.cache_rodas = 0.0
		self.cache_sensors = {
			"sensor_front": 1.0,
			"sensor_left": 1.0,
			"sensor_left_2": 1.0,
			"sensor_right": 1.0,
			"sensor_right_2": 1.0
		}

		print("[main] pronto - a iniciar interface Tkinter...")

		# Iniciar a interface Tkinter numa thread separada
		self.ui_thread = threading.Thread(target=self._init_tkinter, daemon=True)
		self.ui_thread.start()

	def _init_tkinter(self) -> None:
		"""Configura e corre a janela do Tkinter."""
		self.root = tk.Tk()
		self.root.title("Telemetria do Carro - Godot")
		self.root.geometry("340x460")
		self.root.configure(bg="#1e1e1e")
		self.root.resizable(False, False)

		style = ttk.Style()
		style.theme_use("clam")

		# Título da Janela
		lbl_title = tk.Label(
			self.root, 
			text="TELEMETRIA DO CARRO", 
			fg="#00ffcc", 
			bg="#1e1e1e", 
			font=("Arial", 13, "bold")
		)
		lbl_title.pack(pady=10)

		# --- Frame de Estado do Veículo ---
		frame_stats = tk.LabelFrame(
			self.root, 
			text=" Estado do Veículo ", 
			fg="white", 
			bg="#1e1e1e", 
			font=("Arial", 10, "bold")
		)
		frame_stats.pack(fill="x", padx=15, pady=5)

		self.lbl_vel = tk.Label(frame_stats, text="Velocidade: 0.0 km/h", fg="white", bg="#1e1e1e", anchor="w")
		self.lbl_vel.pack(fill="x", padx=10, pady=2)

		self.lbl_rumo = tk.Label(frame_stats, text="Rumo: 0.0°", fg="white", bg="#1e1e1e", anchor="w")
		self.lbl_rumo.pack(fill="x", padx=10, pady=2)

		self.lbl_rodas = tk.Label(frame_stats, text="Ângulo Rodas: 0.0°", fg="white", bg="#1e1e1e", anchor="w")
		self.lbl_rodas.pack(fill="x", padx=10, pady=2)

		# --- Frame de Sensores (RayCasts) ---
		frame_sensors = tk.LabelFrame(
			self.root, 
			text=" Sensores (RayCasts) ", 
			fg="white", 
			bg="#1e1e1e", 
			font=("Arial", 10, "bold")
		)
		frame_sensors.pack(fill="x", padx=15, pady=10)

		self.sensor_bars = {}
		sensor_configs = [
			("Frontal", "sensor_front"),
			("Esquerda 1", "sensor_left"),
			("Esquerda 2", "sensor_left_2"),
			("Direita 1", "sensor_right"),
			("Direita 2", "sensor_right_2")
		]

		for label_text, attr_name in sensor_configs:
			f = tk.Frame(frame_sensors, bg="#1e1e1e")
			f.pack(fill="x", padx=10, pady=3)
			
			lbl = tk.Label(f, text=f"{label_text}:", fg="#cccccc", bg="#1e1e1e", width=11, anchor="w")
			lbl.pack(side="left")
			
			bar = ttk.Progressbar(f, orient="horizontal", length=150, mode="determinate", maximum=1.0)
			bar.pack(side="right", expand=True, fill="x")
			self.sensor_bars[attr_name] = bar

		# Iniciar o ciclo de atualização periódica da UI
		self._update_tkinter_ui()
		self.root.mainloop()

	def _update_tkinter_ui(self) -> None:
		"""Lê os dados da CACHE segura (thread secundária)."""
		with self.lock:
			v = self.cache_vel
			r = self.cache_rumo
			a = self.cache_rodas
			sensors = self.cache_sensors.copy()

		try:
			self.lbl_vel.config(text=f"Velocidade: {v:.1f} km/h")
			self.lbl_rumo.config(text=f"Rumo: {r:.1f}°")
			self.lbl_rodas.config(text=f"Ângulo Rodas: {a:.1f}°")

			for attr, bar in self.sensor_bars.items():
				bar['value'] = sensors.get(attr, 1.0)
		except Exception:
			pass

		if hasattr(self, 'root') and self.root:
			self.root.after(50, self._update_tkinter_ui)

	def _physics_process(self, delta: float) -> None:
		"""Chamado a cada tick de física pelo Godot (thread principal)."""
		self.tempo += delta

		if self.tempo < FIM_ACELERAR:
			self.carro.acelerar(1.0)
		elif self.tempo < FIM_RECUAR:
			self.carro.recuar(1.0)
		else:
			self.carro.largar_pedal()
		self.carro.virar(0.0)

		# 1. Lê os dados do carro de forma segura na thread principal
		v = self.carro.velocidade
		r = self.carro.rumo
		a = self.carro.angulo_rodas
		
		s_data = {
			"sensor_front": self.carro.sensor_front,
			"sensor_left": self.carro.sensor_left,
			"sensor_left_2": self.carro.sensor_left_2,
			"sensor_right": self.carro.sensor_right,
			"sensor_right_2": self.carro.sensor_right_2
		}

		# 2. Atualiza a cache com um bloqueio seguro
		with self.lock:
			self.cache_vel = v
			self.cache_rumo = r
			self.cache_rodas = a
			self.cache_sensors = s_data

		if self.tempo >= self.proximo_print:
			self.proximo_print += INTERVALO_PRINT
			print("[main] velocidade=%.0f km/h | rumo=%.0f° | rodas=%.0f°" % (v, r, a))
