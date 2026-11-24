"""Avaliação independente de cada modelo em pistas fixas, sem aprendizagem."""
from pathlib import Path
import csv
import json
import os
import shutil
import statistics
import time
import numpy as np
from ml.treino.experiencias import nova_execucao, proveniencia, escrever_json, sha256

MODELOS = ("ppo_mlp", "sac_mlp", "ppo_lstm")


class Politica:
    """Uma instância por carro/modelo; memória reiniciada em cada episódio."""
    def __init__(self, nome, caminho):
        self.nome = nome
        if nome == "ppo_lstm":
            from sb3_contrib import RecurrentPPO
            self.modelo = RecurrentPPO.load(str(caminho), device="cpu")
            if self.modelo.observation_space.shape != (7,) or self.modelo.action_space.shape != (2,):
                raise ValueError("Checkpoint LSTM incompatível com o ambiente")
            if not np.allclose(self.modelo.action_space.low, -1) or not np.allclose(self.modelo.action_space.high, 1):
                raise ValueError("Limites de ações LSTM incompatíveis")
        else:
            self.rede = json.loads(Path(caminho).read_text(encoding="utf-8"))
            if nome == "sac_mlp" and (self.rede.get("algoritmo") != "SAC" or self.rede.get("observacoes") != 7):
                raise ValueError("JSON SAC incompatível")
        self.reiniciar()

    def reiniciar(self):
        self.memoria = None
        self.inicio = np.array([True], dtype=bool)

    def prever(self, obs):
        if self.nome == "ppo_lstm":
            acao, self.memoria = self.modelo.predict(np.asarray(obs, dtype=np.float32),
                state=self.memoria, episode_start=self.inicio, deterministic=True)
            self.inicio[:] = False
        elif self.nome == "ppo_mlp":
            from ml.modelos.ppo_modelo import prever
            acao = prever(self.rede["camadas"], obs)
        else:
            from ml.modelos.sac_modelo import prever
            acao = prever(self.rede, obs)
        acao = np.asarray(acao, dtype=np.float32)
        if acao.shape != (2,) or not np.isfinite(acao).all() or np.any(np.abs(acao) > 1.00001):
            raise ValueError("Ação inválida na avaliação de " + self.nome)
        return acao


def carregar_seeds(projeto, conjunto):
    if conjunto not in ("validacao", "teste"):
        raise ValueError("Conjunto deve ser validacao ou teste")
    dados = json.loads((Path(projeto) / "configuracoes/pistas.json").read_text(encoding="utf-8"))
    todas = dados["validacao"] + dados["teste"]
    if len(set(todas)) != len(todas) or any(type(s) is not int or not 2**30 <= s < 2**31 for s in todas):
        raise ValueError("Seeds reservadas devem ser únicas e estar entre 2**30 e 2**31")
    if not dados[conjunto]:
        raise ValueError("Conjunto de pistas vazio")
    return dados[conjunto]


def resumir(linhas):
    resultado = {}
    for nome in sorted(set(l["modelo"] for l in linhas)):
        grupo = [l for l in linhas if l["modelo"] == nome]
        tempos = [l["tempo_conclusao_s"] for l in grupo if l["sucesso"]]
        recompensas = [l["recompensa"] for l in grupo]
        resultado[nome] = {
            "episodios": len(grupo),
            "taxa_conclusao": sum(l["sucesso"] for l in grupo) / len(grupo),
            "taxa_colisao": sum(l["batidas"] > 0 for l in grupo) / len(grupo),
            "progresso_medio": statistics.mean(l["progresso_fracao"] for l in grupo),
            "recompensa_media": statistics.mean(recompensas),
            "recompensa_desvio_pistas": statistics.stdev(recompensas) if len(grupo) > 1 else None,
            "tempo_medio_concluidos_s": statistics.mean(tempos) if tempos else None,
            "tempo_mediano_concluidos_s": statistics.median(tempos) if tempos else None,
        }
    return resultado


def avaliar(env, projeto, conjunto="validacao", contexto=None, *, seeds=None, nomes=MODELOS, pasta_modelos=None):
    """Mesma pista e regra para cada modelo: uma volta, colisão ou 1600 passos."""
    projeto = Path(projeto)
    seeds = carregar_seeds(projeto, conjunto) if seeds is None else list(seeds)
    if not seeds or not nomes:
        raise ValueError("Avaliação sem pistas ou modelos")
    origem = Path(pasta_modelos) if pasta_modelos else projeto / "ml" / "pesos"
    fontes = {nome: origem / (nome + (".zip" if nome == "ppo_lstm" else ".json")) for nome in nomes}
    for nome, p in fontes.items():
        if nome not in MODELOS or not p.is_file():
            raise FileNotFoundError("Falta modelo para avaliação: " + str(p))
    base = Path(os.environ.get("AVALIACAO_PASTA_SAIDA", str(projeto / "resultados")))
    saida = nova_execucao(base, conjunto)
    (saida / "modelos").mkdir()
    politicas = {}
    for nome, p in fontes.items():
        copia = saida / "modelos" / p.name
        shutil.copyfile(p, copia)
        politicas[nome] = Politica(nome, copia)
    meta = proveniencia(projeto)
    meta.update({"conjunto": conjunto, "seeds": seeds, "contexto_godot": contexto or {},
                 "estado": "a_avaliar", "regra": "uma volta ou primeira colisao ou 1600 passos",
                 "modelos_sha256": {nome: sha256(saida / "modelos" / p.name) for nome, p in fontes.items()}})
    escrever_json(saida / "configuracao.json", meta)
    campos = ["modelo", "seed", "sucesso", "motivo", "batidas", "passos", "progresso_fracao",
              "recompensa", "tempo_simulado_s", "tempo_conclusao_s", "tempo_real_s"]
    linhas = []
    try:
        with open(saida / "episodios.csv", "w", newline="", encoding="utf-8") as f:
            csv_out = csv.DictWriter(f, fieldnames=campos)
            csv_out.writeheader()
            for nome, politica in politicas.items():
                for seed in seeds:
                    politica.reiniciar()
                    obs, info = env.reset(seed=seed)
                    recompensa = 0.0
                    passos = 0
                    inicio = time.perf_counter()
                    while True:
                        obs, r, terminado, truncado, info = env.step(politica.prever(obs))
                        recompensa += r
                        passos += 1
                        if terminado or truncado:
                            break
                        if passos >= 1600:
                            raise RuntimeError("Ambiente ultrapassou o limite de avaliação sem terminar")
                    sucesso = info["motivo"] == "volta"
                    linha = dict(modelo=nome, seed=seed, sucesso=sucesso, motivo=info["motivo"],
                        batidas=int(info["batidas"]), passos=passos, progresso_fracao=info["progresso_fracao"],
                        recompensa=recompensa, tempo_simulado_s=info["tempo_simulado_s"],
                        tempo_conclusao_s=info["tempo_simulado_s"] if sucesso else None,
                        tempo_real_s=time.perf_counter() - inicio)
                    linhas.append(linha)
                    csv_out.writerow(linha)
                    f.flush()
                    escrever_json(saida / "resumo.json", resumir(linhas))
                    print(f"[avaliacao] {nome} seed={seed}: {info['motivo']} ({passos} passos)", flush=True)
        meta["estado"] = "concluido"
    except BaseException as erro:
        meta["estado"] = "incompleto"
        meta["erro"] = str(erro) or type(erro).__name__
        raise
    finally:
        meta["episodios_registados"] = len(linhas)
        escrever_json(saida / "configuracao.json", meta)
        env.close()
    print("[avaliacao] Resultados:", saida, flush=True)
    return str(saida)
