"""Lado Python da ligação local com scripts/rl/ponte_rl.gd.

Abre o Godot, recebe a ligação TCP da ponte e troca mensagens JSON por linha.
"""
import json
import socket
import subprocess
from pathlib import Path


class ClienteGodot:
    def __init__(self, projeto: str, godot: str | None, cena: str, porta: int, modo: str):
        self.projeto = Path(projeto).resolve()
        self.godot = godot
        self.cena = cena
        self.porta = porta
        self.modo = modo
        if godot is None:
            self.sock = socket.create_connection(("127.0.0.1", porta), timeout=45)
        else:
            self._abrir_godot()
        self.sock.settimeout(30)
        self.buffer = b""
        try:
            mensagem = self._receber()
            if mensagem.get("type") != "hello":
                raise RuntimeError(f"Resposta inesperada do Godot: {mensagem}")
        except Exception:
            self.close()
            raise
        print("Conectado:", mensagem, flush=True)

    def _abrir_godot(self):
        self.servidor = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.servidor.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.servidor.bind(("127.0.0.1", self.porta))
        self.servidor.listen(1)
        self.servidor.settimeout(45)
        comando = [self.godot]
        if self.modo == "train":
            comando.append("--headless")
        comando += ["--path", str(self.projeto), self.cena, "--", f"--rl-{self.modo}", "--rl-port", str(self.porta)]
        print("Iniciando Godot:", " ".join(comando), flush=True)
        self.processo = subprocess.Popen(comando, cwd=self.projeto)
        try:
            self.sock, _ = self.servidor.accept()
        except Exception:
            self.close()
            raise RuntimeError("Godot não conectou em 45s. Confirme o caminho do Godot, a cena e o nó PonteRL.")

    def _receber(self):
        while b"\n" not in self.buffer:
            dados = self.sock.recv(65536)
            if not dados:
                raise ConnectionError("Godot desconectou do Python")
            self.buffer += dados
        linha, self.buffer = self.buffer.split(b"\n", 1)
        msg = json.loads(linha.decode("utf-8"))
        if msg.get("type") == "error":
            raise RuntimeError(msg.get("message", "Erro do Godot"))
        return msg

    def comando(self, cmd: str, *, tempo_limite: float | None = 30, **dados):
        self.sock.sendall((json.dumps({"cmd": cmd, **dados}) + "\n").encode("utf-8"))
        self.sock.settimeout(tempo_limite)
        try:
            resultado = self._receber()
        finally:
            self.sock.settimeout(30)
        if resultado.get("type") != cmd:
            raise RuntimeError(f"Esperava {cmd}; recebi {resultado.get('type')}")
        return resultado

    def aguardar_fecho(self):
        self.sock.settimeout(None)
        while self.sock.recv(65536):
            pass

    def close(self):
        if hasattr(self, "sock"):
            try:
                if self.godot is not None:
                    self.sock.sendall(b'{"cmd":"close"}\n')
            except OSError:
                pass
            finally:
                self.sock.close()
        if hasattr(self, "servidor"):
            self.servidor.close()
        if hasattr(self, "processo") and self.processo.poll() is None:
            try:
                self.processo.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.processo.terminate()
                try:
                    self.processo.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.processo.kill()


if __name__ == "__main__":
    print("Importe ClienteGodot de outro script.")
