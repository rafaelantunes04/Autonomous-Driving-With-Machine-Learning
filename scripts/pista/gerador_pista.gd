extends RefCounted
class_name GeradorPista

## Gera a linha central e as bordas da pista. Não toca em cenas nem em física.
##
## Tudo o que depende do número de pontos escala com ele:
##  - os raios (raio_min / raio_max são os valores para PONTOS_REFERENCIA pontos),
##    para o espaçamento entre pontos se manter ~constante;
##  - o ruído do ângulo (fração do passo angular);
##  - a variação do raio entre pontos vizinhos (passo máximo ligado ao espaçamento),
##    para as curvas nunca ficarem mais apertadas do que a largura da pista aguenta.
## A largura da pista NÃO escala (o carro tem tamanho fixo).

const PONTOS_REFERENCIA := 12
const FRACAO_RUIDO_ANGULO := 0.28     # do passo angular entre pontos
const FRACAO_PASSO_RAIO := 0.5        # variação máx. de raio entre vizinhos / espaçamento
const AMOSTRA_PROXIMIDADE := 5        # compara 1 em cada N pontos da linha central
const MARGEM_CURVA := 15.0            # px acima de metade da largura
const MARGEM_PROXIMIDADE := 20.0      # px acima da largura, entre troços distantes

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


## Gera a linha central. Mesma seed = mesma pista.
## Tenta variantes da seed até não haver curvas apertadas nem troços colados.
func gerar(seed_: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	var linha := PackedVector2Array()
	for tentativa in 300:
		rng.seed = seed_ * 1000 + tentativa
		linha = _linha_central_aleatoria(rng)
		if _raio_minimo(linha) > largura * 0.5 + MARGEM_CURVA \
				and _distancia_minima_entre_trocos(linha) > largura + MARGEM_PROXIMIDADE:
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


## Raios dos pontos de controlo: passeio aleatório fechado (o último passo volta ao
## início), com passo limitado pelo espaçamento. Assim, vizinhos têm raios parecidos
## e a curva não faz zig-zags impossíveis quando há muitos pontos.
func _raios_aleatorios(rng: RandomNumberGenerator) -> Array[float]:
	var esc := escala()
	var r_min := raio_min * esc
	var r_max := raio_max * esc
	var r_medio := (r_min + r_max) * 0.5
	var espacamento := TAU * r_medio / num_pontos          # ~constante com o nº de pontos
	var passo_max := espacamento * FRACAO_PASSO_RAIO

	var w: Array[float] = [0.0]
	for i in range(1, num_pontos + 1):
		w.append(w[i - 1] + rng.randf_range(-passo_max, passo_max))
	var deriva := w[num_pontos]
	var soma := 0.0
	for i in num_pontos:
		w[i] -= deriva * i / num_pontos                    # fecha o passeio
		soma += w[i]
	var media := soma / num_pontos

	var raios: Array[float] = []
	for i in num_pontos:
		raios.append(clampf(r_medio + w[i] - media, r_min, r_max))
	return raios


## Pontos aleatórios à volta de um círculo, ligados por uma curva fechada e suave
func _linha_central_aleatoria(rng: RandomNumberGenerator) -> PackedVector2Array:
	var passo_angulo := TAU / num_pontos
	var ruido := passo_angulo * FRACAO_RUIDO_ANGULO
	var raios := _raios_aleatorios(rng)

	var pts: Array[Vector2] = []
	for i in num_pontos:
		var angulo := passo_angulo * i + rng.randf_range(-ruido, ruido)
		pts.append(Vector2.from_angle(angulo) * raios[i])

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


## Menor distância entre dois troços da pista que estão longe um do outro ao longo
## do percurso (evita bordas a sobrepor-se / pista a tocar nela própria).
func _distancia_minima_entre_trocos(linha: PackedVector2Array) -> float:
	var amostra := PackedVector2Array()
	for i in range(0, linha.size(), AMOSTRA_PROXIMIDADE):
		amostra.append(linha[i])
	var m := amostra.size()
	var separacao_min := ceili(largura * 2.0 / (10.0 * AMOSTRA_PROXIMIDADE)) + 8
	var min_d2 := INF
	for i in m:
		for j in range(i + 1, m):
			var sep := mini(j - i, m - (j - i))
			if sep <= separacao_min:
				continue
			min_d2 = minf(min_d2, amostra[i].distance_squared_to(amostra[j]))
	return sqrt(min_d2)
