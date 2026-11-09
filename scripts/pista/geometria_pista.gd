extends RefCounted
class_name GeometriaPista

## Funções de geometria partilhadas pelo gerador aleatório e pela Pista:
## curva -> linha central -> bordas, e validação (curvas apertadas, troços colados).
## Tudo estático e sem cenas nem física.

const ESPACAMENTO := 10.0             # px entre pontos da linha central amostrada
const AMOSTRA_PROXIMIDADE := 5        # compara 1 em cada N pontos da linha central
const MARGEM_CURVA := 15.0            # px acima de metade da largura
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


## Amostra a curva (fechada) em pontos igualmente espaçados: a linha central.
## O último ponto, que coincide com o primeiro, é removido.
static func amostrar(curva: Curve2D) -> PackedVector2Array:
	var pontos := fechar(curva).tessellate_even_length(6, ESPACAMENTO)
	if pontos.size() > 1:
		pontos.remove_at(pontos.size() - 1)
	return pontos


## Calcula as bordas a partir da linha central.
## Devolve {"esquerda": PackedVector2Array, "direita": PackedVector2Array}
static func calcular_bordas(linha: PackedVector2Array, largura: float) -> Dictionary:
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


## Raio de curvatura mínimo estimado ao longo da linha central
static func raio_minimo(linha: PackedVector2Array) -> float:
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
