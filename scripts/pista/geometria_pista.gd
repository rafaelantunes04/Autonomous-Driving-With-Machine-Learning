extends RefCounted
class_name GeometriaPista

## Funções de geometria partilhadas pelo gerador aleatório e pela Pista:
## curva -> linha central -> bordas, e validação (curvas apertadas, troços colados).
## Tudo estático e sem cenas nem física.

const ESPACAMENTO := 10.0             # px entre pontos da linha central amostrada
const AMOSTRA_PROXIMIDADE := 5        # compara 1 em cada N pontos da linha central
const MARGEM_CURVA := 30.0            # px acima de metade da largura
const INTERVALO_BAKE := 2.0           # px entre pontos da curva «cozida» (precisão da amostragem)
const TENSAO_SPLINE := 0.33           # comprimento dos handles / distância ao vizinho
const PASSO_CURVATURA := 3            # raio de curvatura medido entre pontos i-3, i, i+3
const MARGEM_PROXIMIDADE := 20.0      # px acima da largura, entre troços distantes


## Fecha a curva se o último ponto não coincidir com o primeiro. Não altera a original.
static func fechar(curva: Curve2D) -> Curve2D:
	var n := curva.point_count
	if n < 2:
		return curva
	if curva.get_point_position(0).distance_to(curva.get_point_position(n - 1)) < 1.0:
		return curva
	var fechada := curva.duplicate() as Curve2D
	fechada.add_point(fechada.get_point_position(0))
	return fechada


## Cria uma curva fechada e suave (sem cantos nem overshoot) que passa por todos os
## pontos. Os handles apontam na direção média entre o troço que chega e o que sai e
## têm comprimento proporcional a cada troço, por isso a curva não faz «picos» quando
## os pontos estão desigualmente espaçados. O último ponto repete o primeiro.
static func curva_suave(pts: Array[Vector2]) -> Curve2D:
	var n := pts.size()
	var curva := Curve2D.new()
	for i in n + 1:
		var p := pts[i % n]
		var antes := p - pts[(i - 1 + n) % n]
		var depois := pts[(i + 1) % n] - p
		var t := antes.normalized() + depois.normalized()
		t = t.normalized() if t.length_squared() > 0.0001 else depois.normalized()
		curva.add_point(p, -t * antes.length() * TENSAO_SPLINE, t * depois.length() * TENSAO_SPLINE)
	return curva


## Se a curva é uma poligonal (nenhum ponto tem handles, como um Path2D desenhado só
## com cliques), devolve uma versão suavizada que passa pelos mesmos pontos. Se já
## tem handles, devolve-a tal como está. Não altera a original.
static func suavizar_poligonal(curva: Curve2D) -> Curve2D:
	var n := curva.point_count
	if n < 3:
		return curva
	for i in n:
		if curva.get_point_in(i) != Vector2.ZERO or curva.get_point_out(i) != Vector2.ZERO:
			return curva
	var pts: Array[Vector2] = []
	for i in n:
		pts.append(curva.get_point_position(i))
	if pts[0].distance_to(pts[n - 1]) < 1.0:
		pts.remove_at(n - 1)
	if pts.size() < 3:
		return curva
	return curva_suave(pts)


## Amostra a curva (fechada) em pontos IGUALMENTE espaçados ao longo do percurso: a
## linha central. O espaçamento é ajustado para dar um número inteiro de pontos, de
## modo a que a curva feche sem emenda. Usa a curva «cozida» com passo pequeno, o que
## evita as arestas e o espaçamento irregular do tessellate_even_length.
static func amostrar(curva: Curve2D) -> PackedVector2Array:
	var c := suavizar_poligonal(fechar(curva)).duplicate() as Curve2D
	c.bake_interval = INTERVALO_BAKE
	var comprimento := c.get_baked_length()
	var pontos := PackedVector2Array()
	if comprimento <= 0.0:
		return pontos
	var n := maxi(roundi(comprimento / ESPACAMENTO), 8)
	var passo := comprimento / n
	for i in n:
		pontos.append(c.sample_baked(i * passo, true))
	return pontos


## Calcula as bordas a partir da linha central. Em cada ponto o deslocamento é feito
## ao longo da média das normais dos dois segmentos vizinhos e corrigido (mitra) para
## a pista ter sempre a mesma largura, mesmo nas curvas.
## Devolve {"esquerda": PackedVector2Array, "direita": PackedVector2Array}
static func calcular_bordas(linha: PackedVector2Array, largura: float) -> Dictionary:
	var n := linha.size()
	var esquerda := PackedVector2Array()
	var direita := PackedVector2Array()
	esquerda.resize(n)
	direita.resize(n)
	for i in n:
		var d1 := (linha[i] - linha[(i - 1 + n) % n]).normalized()
		var d2 := (linha[(i + 1) % n] - linha[i]).normalized()
		var n1 := Vector2(-d1.y, d1.x)
		var n2 := Vector2(-d2.y, d2.x)
		var normal := n1 + n2
		normal = normal.normalized() if normal.length_squared() > 0.0001 else n2
		var mitra := 1.0 / maxf(normal.dot(n2), 0.5)
		var deslocamento := normal * (largura * 0.5 * mitra)
		esquerda[i] = linha[i] + deslocamento
		direita[i] = linha[i] - deslocamento
	return {"esquerda": esquerda, "direita": direita}


## Lista de problemas que a pista tem para esta largura (vazia = pista válida).
static func problemas(linha: PackedVector2Array, largura: float) -> PackedStringArray:
	var lista := PackedStringArray()
	var raio_necessario := largura * 0.5 + MARGEM_CURVA
	var raio := raio_minimo(linha)
	if raio <= raio_necessario:
		lista.append("curva demasiado apertada para a largura (raio mínimo %.0f px, precisa de mais de %.0f px)" % [raio, raio_necessario])
	var distancia_necessaria := largura + MARGEM_PROXIMIDADE
	var distancia := distancia_minima_entre_trocos(linha, largura)
	if distancia <= distancia_necessaria:
		lista.append("troços da pista demasiado próximos (%.0f px, precisa de mais de %.0f px)" % [distancia, distancia_necessaria])
	return lista


## Raio de curvatura mínimo ao longo da linha central: raio da circunferência que
## passa por três pontos (i - k, i, i + k). Reto = infinito.
static func raio_minimo(linha: PackedVector2Array) -> float:
	var n := linha.size()
	var min_r := INF
	for i in n:
		var a := linha[(i - PASSO_CURVATURA + n) % n]
		var b := linha[i]
		var c := linha[(i + PASSO_CURVATURA) % n]
		var dobro_area := absf((b - a).cross(c - a))
		if dobro_area > 0.0001:
			min_r = minf(min_r, a.distance_to(b) * b.distance_to(c) * a.distance_to(c) / (2.0 * dobro_area))
	return min_r


## Menor distância entre dois troços da pista que estão longe um do outro ao longo
## do percurso (evita bordas a sobrepor-se / pista a tocar nela própria).
static func distancia_minima_entre_trocos(linha: PackedVector2Array, largura: float) -> float:
	var amostra := PackedVector2Array()
	for i in range(0, linha.size(), AMOSTRA_PROXIMIDADE):
		amostra.append(linha[i])
	var m := amostra.size()
	var separacao_min := ceili(largura * 2.0 / (ESPACAMENTO * AMOSTRA_PROXIMIDADE)) + 8
	var min_d2 := INF
	for i in m:
		for j in range(i + 1, m):
			var sep := mini(j - i, m - (j - i))
			if sep <= separacao_min:
				continue
			min_d2 = minf(min_d2, amostra[i].distance_squared_to(amostra[j]))
	return sqrt(min_d2)
