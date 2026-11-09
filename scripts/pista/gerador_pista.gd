extends RefCounted
class_name GeradorPista

## Gera uma pista aleatória como Curve2D (o mesmo tipo que um Path2D desenhado à
## mão). A Pista trata as duas origens da mesma forma. Não toca em cenas nem em física.
##
## Como funciona: o raio ao longo do ângulo é uma soma de poucas ondas (harmónicas),
## o que dá curvas grandes e suaves em vez de altos e baixos aleatórios; a cada ponto
## junta-se só um pouco de irregularidade. Os pontos são ligados por uma spline
## fechada sem overshoot (GeometriaPista.curva_suave). Se a pista tiver curvas
## apertadas ou troços colados, tenta-se outra variante da mesma seed.
##
## Os raios (raio_min / raio_max) são os valores para PONTOS_REFERENCIA pontos e
## escalam com o número de pontos, para o espaçamento entre pontos ser ~constante.
## A largura da pista NÃO escala (o carro tem tamanho fixo).

const PONTOS_REFERENCIA := 12
const FRACAO_RUIDO_ANGULO := 0.2      # do passo angular entre pontos
const HARMONICA_MIN := 2              # nº de «lóbulos» da forma base (1 só desloca o centro)
const HARMONICA_MAX := 5
const FRACAO_IRREGULARIDADE := 0.07   # ruído por ponto, como fração de (raio_max - raio_min)

var largura: float
var num_pontos: int
var raio_min: float   # para PONTOS_REFERENCIA pontos
var raio_max: float


func _init(p_largura: float = 120.0, p_num_pontos: int = 12,
		p_raio_min: float = 300.0, p_raio_max: float = 600.0) -> void:
	largura = p_largura
	num_pontos = maxi(p_num_pontos, 4)
	raio_min = p_raio_min
	raio_max = p_raio_max


## Fator de escala: 1.0 com PONTOS_REFERENCIA pontos, 2.0 com o dobro, etc.
func escala() -> float:
	return float(num_pontos) / PONTOS_REFERENCIA


## Gera a curva fechada. Mesma seed = mesma pista.
## Tenta variantes da seed até não haver curvas apertadas nem troços colados.
func gerar_curva(seed_: int) -> Curve2D:
	var rng := RandomNumberGenerator.new()
	var curva: Curve2D
	for tentativa in 300:
		rng.seed = seed_ * 1000 + tentativa
		curva = _curva_aleatoria(rng)
		if GeometriaPista.problemas(GeometriaPista.amostrar(curva), largura).is_empty():
			return curva
	push_warning("Seed %d: nenhuma variante válida, a pista pode ter curvas apertadas" % seed_)
	return curva


## Raios dos pontos de controlo: forma base suave (soma de harmónicas com fase e
## amplitude aleatórias, amplitude a descer com a frequência) normalizada para
## [r_min, r_max], mais um pouco de irregularidade por ponto.
func _raios_aleatorios(rng: RandomNumberGenerator, angulos: Array[float]) -> Array[float]:
	var esc := escala()
	var r_min := raio_min * esc
	var r_max := raio_max * esc

	var amplitude: Array[float] = []
	var fase: Array[float] = []
	for k in range(HARMONICA_MIN, HARMONICA_MAX + 1):
		amplitude.append(rng.randf_range(0.4, 1.0) / k)
		fase.append(rng.randf_range(0.0, TAU))

	# Normalização: valores mínimo e máximo da forma base
	var f_min := INF
	var f_max := -INF
	for i in 360:
		var f := _forma_base(TAU * i / 360.0, amplitude, fase)
		f_min = minf(f_min, f)
		f_max = maxf(f_max, f)

	var ruido := (r_max - r_min) * FRACAO_IRREGULARIDADE
	var raios: Array[float] = []
	for a in angulos:
		var u := inverse_lerp(f_min, f_max, _forma_base(a, amplitude, fase))
		raios.append(clampf(lerpf(r_min, r_max, u) + rng.randf_range(-ruido, ruido), r_min, r_max))
	return raios


func _forma_base(angulo: float, amplitude: Array[float], fase: Array[float]) -> float:
	var f := 0.0
	for i in amplitude.size():
		f += amplitude[i] * cos((HARMONICA_MIN + i) * angulo + fase[i])
	return f


## Pontos à volta de um círculo, ligados por uma curva fechada e suave
func _curva_aleatoria(rng: RandomNumberGenerator) -> Curve2D:
	var passo_angulo := TAU / num_pontos
	var ruido := passo_angulo * FRACAO_RUIDO_ANGULO
	var angulos: Array[float] = []
	for i in num_pontos:
		angulos.append(passo_angulo * i + rng.randf_range(-ruido, ruido))
	var raios := _raios_aleatorios(rng, angulos)

	var pts: Array[Vector2] = []
	for i in num_pontos:
		pts.append(Vector2.from_angle(angulos[i]) * raios[i])
	return GeometriaPista.curva_suave(pts)
