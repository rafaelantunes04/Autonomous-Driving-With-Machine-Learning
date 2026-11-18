"""Janela Tkinter com a telemetria do carro (corre numa thread própria).

O Godot escreve os dados com atualizar() na thread de física; a janela lê-os
da cache protegida por um lock.
"""

import threading
import tkinter as tk
from tkinter import ttk

from carro_api import SENSORES

COR_FUNDO = "#1e1e1e"
COR_TEXTO = "white"
COR_DESTAQUE = "#00ffcc"
INTERVALO_MS = 50


class TelemetriaUI:
	def __init__(self):
		self._lock = threading.Lock()
		self._velocidade = 0.0
		self._rumo = 0.0
		self._rodas = 0.0
		self._sensores = {nome: 1.0 for nome in SENSORES}
		threading.Thread(target=self._correr, daemon=True).start()

	def atualizar(self, velocidade, rumo, rodas, sensores):
		"""Chamado pela thread do Godot: guarda os valores mais recentes."""
		with self._lock:
			self._velocidade, self._rumo, self._rodas = velocidade, rumo, rodas
			self._sensores = dict(sensores)

	# ------------------------------------------------------------ janela

	def _correr(self):
		self._root = tk.Tk()
		self._root.title("Telemetria do Carro - Godot")
		self._root.geometry("340x460")
		self._root.configure(bg=COR_FUNDO)
		self._root.resizable(False, False)
		ttk.Style().theme_use("clam")

		tk.Label(self._root, text="TELEMETRIA DO CARRO", fg=COR_DESTAQUE, bg=COR_FUNDO,
			font=("Arial", 13, "bold")).pack(pady=10)

		estado = self._caixa(" Estado do Veículo ", pady=5)
		self._lbl_vel = self._linha_texto(estado, "Velocidade: 0.0 km/h")
		self._lbl_rumo = self._linha_texto(estado, "Rumo: 0.0°")
		self._lbl_rodas = self._linha_texto(estado, "Ângulo Rodas: 0.0°")

		caixa_sensores = self._caixa(" Sensores (RayCasts) ", pady=10)
		self._barras = {}
		for nome in SENSORES:
			linha = tk.Frame(caixa_sensores, bg=COR_FUNDO)
			linha.pack(fill="x", padx=10, pady=3)
			tk.Label(linha, text=nome + ":", fg="#cccccc", bg=COR_FUNDO, width=11, anchor="w").pack(side="left")
			barra = ttk.Progressbar(linha, orient="horizontal", length=150, mode="determinate", maximum=1.0)
			barra.pack(side="right", expand=True, fill="x")
			self._barras[nome] = barra

		self._refrescar()
		self._root.mainloop()

	def _caixa(self, titulo, pady):
		caixa = tk.LabelFrame(self._root, text=titulo, fg=COR_TEXTO, bg=COR_FUNDO, font=("Arial", 10, "bold"))
		caixa.pack(fill="x", padx=15, pady=pady)
		return caixa

	def _linha_texto(self, pai, texto):
		label = tk.Label(pai, text=texto, fg=COR_TEXTO, bg=COR_FUNDO, anchor="w")
		label.pack(fill="x", padx=10, pady=2)
		return label

	def _refrescar(self):
		with self._lock:
			velocidade, rumo, rodas, sensores = self._velocidade, self._rumo, self._rodas, dict(self._sensores)
		self._lbl_vel.config(text=f"Velocidade: {velocidade:.1f} km/h")
		self._lbl_rumo.config(text=f"Rumo: {rumo:.1f}°")
		self._lbl_rodas.config(text=f"Ângulo Rodas: {rodas:.1f}°")
		for nome, barra in self._barras.items():
			barra["value"] = sensores.get(nome, 1.0)
		self._root.after(INTERVALO_MS, self._refrescar)
