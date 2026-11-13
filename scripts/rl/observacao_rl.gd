extends RefCounted
class_name ObservacaoRL
## Posição do carro na pista e as 8 observações do modelo PPO, calculadas dentro
## do Godot. A ordem dos valores faz parte da interface com o modelo treinado:
## não a mudes (nem treino nem corrida_ppo.py funcionam com outra ordem).

const TAMANHO: int = 8

var comprimento: float = 0.0   ## comprimento da linha central, em px

var _pista: Pista
var _distancias := PackedFloat32Array()


func _init(pista: Pista) -> void:
	_pista = pista
	_pista.pista_alterada.connect(invalidar)


func invalidar() -> void:
	_distancias = PackedFloat32Array()


func _preparar() -> void:
	var linha: PackedVector2Array = _pista.centerline
	_distancias = PackedFloat32Array()
	comprimento = 0.0
	var n := linha.size()
	for i in range(n):
		_distancias.append(comprimento)
		comprimento += linha[i].distance_to(linha[(i + 1) % n])


## progresso (px ao longo da linha central), lateral (px, com sinal), tangente e alvo.
func localizar(pos_global: Vector2) -> Dictionary:
	var linha: PackedVector2Array = _pista.centerline
	if linha.size() < 2:
		return {"progresso": 0.0, "lateral": 0.0, "tangente": Vector2.RIGHT, "alvo": Vector2.RIGHT}
	if _distancias.size() != linha.size():
		_preparar()

	var pos: Vector2 = _pista.to_local(pos_global)
	var melhor_d: float = INF
	var melhor_i: int = 0
	var melhor_t: float = 0.0
	var melhor_p := Vector2.ZERO
	var n := linha.size()
	for i in range(n):
		var a: Vector2 = linha[i]
		var b: Vector2 = linha[(i + 1) % n]
		var ab: Vector2 = b - a
		var t: float = clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var p: Vector2 = a + ab * t
		var d: float = pos.distance_squared_to(p)
		if d < melhor_d:
			melhor_d = d
			melhor_i = i
			melhor_t = t
			melhor_p = p

	var tangente: Vector2 = (linha[(melhor_i + 1) % n] - linha[melhor_i]).normalized()
	var normal := Vector2(-tangente.y, tangente.x)
	return {
		"progresso": _distancias[mini(melhor_i, _distancias.size() - 1)] + linha[melhor_i].distance_to(linha[(melhor_i + 1) % n]) * melhor_t,
		"lateral": (pos - melhor_p).dot(normal),
		"tangente": tangente,
		"alvo": linha[(melhor_i + 15) % n] - pos,
	}


func calcular(carro: Carro) -> PackedFloat32Array:
	if _pista.centerline.size() < 2:
		return PackedFloat32Array([0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0])
	var loc := localizar(carro.global_position)
	var tangente: Vector2 = loc["tangente"]
	var alvo: Vector2 = loc["alvo"]
	var angulo: float = wrapf(carro.global_rotation - tangente.rotated(_pista.global_rotation).angle(), -PI, PI)
	var alvo_angulo: float = wrapf(alvo.rotated(_pista.global_rotation).angle() - carro.global_rotation, -PI, PI)
	var vmax: float = maxf(carro.velocidade_max, 1.0)
	return PackedFloat32Array([
		clampf(carro.velocity.dot(carro.transform.x) / vmax, -1.0, 1.0),
		clampf(float(loc["lateral"]) / maxf(_pista.largura * 0.5, 1.0), -3.0, 3.0),
		sin(angulo), cos(angulo), sin(alvo_angulo), cos(alvo_angulo),
		clampf(carro.direcao_rodas / deg_to_rad(30.0), -1.0, 1.0),
		clampf(carro.velocity.length() / vmax, 0.0, 1.0),
	])
