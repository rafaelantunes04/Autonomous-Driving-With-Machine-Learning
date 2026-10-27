extends RefCounted
class_name GeradorPista

## Gera a linha central e as bordas da pista. Não toca em cenas nem em física.

var largura: float
var num_pontos: int
var raio_min: float
var raio_max: float


func _init(p_largura: float = 120.0, p_num_pontos: int = 12,
		p_raio_min: float = 300.0, p_raio_max: float = 600.0) -> void:
	largura = p_largura
	num_pontos = p_num_pontos
	raio_min = p_raio_min
	raio_max = p_raio_max


## Gera a linha central. Mesma seed = mesma pista.
## Tenta variantes da seed até não haver curvas apertadas demais.
func gerar(seed_: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	var linha := PackedVector2Array()
	for tentativa in 200:
		rng.seed = seed_ * 1000 + tentativa
		linha = _linha_central_aleatoria(rng)
		if _raio_minimo(linha) > largura * 0.5 + 15.0:
			return linha
	push_warning("Seed %d: nenhuma variante válida, a pista pode ter curvas apertadas" % seed_)
	return linha


## Calcula as bordas a partir da linha central.
## Devolve {"esquerda": PackedVector2Array, "direita": PackedVector2Array}
func calcular_bordas(linha: PackedVector2Array) -> Dictionary:
	var n := linha.size()
	var esquerda := PackedVector2Array()
	var direita := PackedVector2Array()
	esquerda.resize(n)
	direita.resize(n)
	for i in n:
		var t := (linha[(i + 1) % n] - linha[(i - 1 + n) % n]).normalized()
		var deslocamento := Vector2(-t.y, t.x) * largura * 0.5
		esquerda[i] = linha[i] + deslocamento
		direita[i] = linha[i] - deslocamento
	return {"esquerda": esquerda, "direita": direita}


## Pontos aleatórios à volta de um círculo, ligados por uma curva fechada e suave
func _linha_central_aleatoria(rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	for i in num_pontos:
		var angulo := TAU * i / num_pontos + rng.randf_range(-0.15, 0.15)
		pts.append(Vector2.from_angle(angulo) * rng.randf_range(raio_min, raio_max))

	var curva := Curve2D.new()
	for i in num_pontos + 1:  # o último ponto repete o primeiro para fechar
		var h := (pts[(i + 1) % num_pontos] - pts[(i - 1 + num_pontos) % num_pontos]) / 6.0
		curva.add_point(pts[i % num_pontos], -h, h)

	var amostrada := curva.tessellate_even_length(6, 10.0)
	amostrada.remove_at(amostrada.size() - 1)  # o último ponto coincide com o primeiro
	return amostrada


## Raio de curvatura mínimo estimado ao longo da linha central
func _raio_minimo(linha: PackedVector2Array) -> float:
	var n := linha.size()
	var min_r := INF
	for i in n:
		var a := linha[i] - linha[(i - 3 + n) % n]
		var b := linha[(i + 3) % n] - linha[i]
		var ang := absf(a.angle_to(b))
		if ang > 0.001:
			min_r = minf(min_r, (a.length() + b.length()) * 0.5 / ang)
	return min_r
