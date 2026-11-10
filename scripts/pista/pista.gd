@tool
extends Node2D
class_name Pista

## Só a geometria da pista: linha central, bordas, paredes de colisão, desenho e
## ponto de partida. Não conhece carros, HUD nem câmara (isso é da Corrida).
##
## De onde vem a pista:
##  - Se houver um Path2D, a pista é preenchida à volta dele. Procura-se, por
##    ordem: o `path` do Inspetor, um Path2D filho desta Pista, um Path2D de
##    qualquer sítio da cena no grupo "pista_path". Um Path2D aberto é fechado
##    automaticamente. Um Marker2D filho do Path2D chamado "Partida" põe a
##    linha de partida junto a ele (a direção segue sempre o percurso).
##  - Se não houver (ou tiver menos de 3 pontos), gera-se uma pista aleatória
##    a partir de `semente`, guardada num Path2D interno.
##
## É @tool: no editor a pista atualiza enquanto mexes nos pontos do Path2D.
## As paredes e o Path2D gerado são criados por código e não são gravados na cena.

## Emitido sempre que a pista é (re)construída.
signal pista_alterada

const GRUPO_PATH := &"pista_path"

@export_group("Origem")
## Path2D a usar. Vazio = procura automática (ver acima).
@export var path: Path2D:
	set(valor):
		path = valor
		_pedir_reconstrucao()

@export_group("Forma")
@export var largura: float = 120.0:
	set(valor):
		largura = valor
		_pedir_reconstrucao()

@export_group("Pista aleatória")
@export var semente: int = 0:
	set(valor):
		semente = valor
		_pedir_reconstrucao()
@export var num_pontos: int = 12:
	set(valor):
		num_pontos = valor
		_pedir_reconstrucao()
## Raios para 12 pontos (referência). Escalam sozinhos com num_pontos.
@export var raio_min: float = 300.0:
	set(valor):
		raio_min = valor
		_pedir_reconstrucao()
@export var raio_max: float = 600.0:
	set(valor):
		raio_max = valor
		_pedir_reconstrucao()

# Tudo em coordenadas locais da Pista
var centerline := PackedVector2Array()
var left_border := PackedVector2Array()
var right_border := PackedVector2Array()
var start_position := Vector2.ZERO
var start_rotation := 0.0

var _modo_manual: bool = false
var _path_gerado: Path2D
var _paredes_shape: CollisionShape2D
var _curva_ligada: Curve2D
var _reconstrucao_pendente: bool = false


func _ready() -> void:
	reconstruir()


## True se a pista vem de um Path2D desenhado, false se é aleatória.
func usa_path_manual() -> bool:
	return _modo_manual


## Gera uma pista aleatória nova com esta seed (reconstrói no fim do frame, através
## do setter de `semente`). Sem efeito se a pista vem de um Path2D.
func gerar(seed_: int) -> void:
	if _modo_manual:
		return
	semente = seed_


## Reconstrói linha central, bordas, paredes e desenho a partir do Path2D (ou do gerador).
func reconstruir() -> void:
	var fonte := _encontrar_path()
	if fonte != null and (fonte.curve == null or fonte.curve.point_count < 3):
		push_warning("O Path2D '%s' precisa de pelo menos 3 pontos: a usar pista aleatória." % fonte.name)
		fonte = null

	var curva: Curve2D
	_modo_manual = fonte != null
	if _modo_manual:
		curva = fonte.curve
	else:
		curva = GeradorPista.new(largura, num_pontos, raio_min, raio_max).gerar_curva(semente)
		fonte = _garantir_path_gerado()
		fonte.curve = curva
	_ligar_curva(curva if _modo_manual else null)

	# Curva -> linha central, em coordenadas locais da Pista
	var linha := PackedVector2Array()
	for ponto in GeometriaPista.amostrar(curva):
		linha.append(to_local(fonte.to_global(ponto)))

	if _modo_manual:
		for problema in GeometriaPista.problemas(linha, largura):
			push_warning("Path2D '%s': %s" % [fonte.name, problema])
		var partida := fonte.get_node_or_null("Partida") as Node2D
		if partida != null:
			linha = _rodar_para_partida(linha, to_local(partida.global_position))

	centerline = linha
	var bordas := GeometriaPista.calcular_bordas(centerline, largura)
	left_border = bordas["esquerda"]
	right_border = bordas["direita"]

	# Ponto de partida = primeiro ponto da linha central, virado para o seguinte
	start_position = centerline[0]
	start_rotation = (centerline[1 % centerline.size()] - start_position).angle()

	_atualizar_paredes()
	queue_redraw()
	pista_alterada.emit()


# ------------------------------------------------------------------ Interno

func _encontrar_path() -> Path2D:
	if path != null:
		return path
	for no in find_children("*", "Path2D", true, false):
		if no != _path_gerado:
			return no as Path2D
	for no in get_tree().get_nodes_in_group(GRUPO_PATH):
		if no is Path2D and no != _path_gerado:
			return no as Path2D
	return null


func _garantir_path_gerado() -> Path2D:
	if _path_gerado == null:
		_path_gerado = Path2D.new()
		_path_gerado.name = "PathGerado"
		add_child(_path_gerado)   # sem owner: não é gravado na cena
	return _path_gerado


## Reage a mexer nos pontos do Path2D (no editor ou em jogo).
func _ligar_curva(curva: Curve2D) -> void:
	if curva == _curva_ligada:
		return
	if _curva_ligada != null and _curva_ligada.changed.is_connected(_pedir_reconstrucao):
		_curva_ligada.changed.disconnect(_pedir_reconstrucao)
	_curva_ligada = curva
	if curva != null:
		curva.changed.connect(_pedir_reconstrucao)


## Junta vários pedidos seguidos (ex.: arrastar um ponto) numa só reconstrução.
func _pedir_reconstrucao() -> void:
	if not is_node_ready() or _reconstrucao_pendente:
		return
	_reconstrucao_pendente = true
	_reconstruir_adiado.call_deferred()


func _reconstruir_adiado() -> void:
	_reconstrucao_pendente = false
	reconstruir()


## Roda a linha para o ponto mais próximo de `ponto` passar a ser o índice 0.
func _rodar_para_partida(linha: PackedVector2Array, ponto: Vector2) -> PackedVector2Array:
	var melhor := 0
	var melhor_d := INF
	for i in linha.size():
		var d := linha[i].distance_squared_to(ponto)
		if d < melhor_d:
			melhor_d = d
			melhor = i
	if melhor == 0:
		return linha
	return linha.slice(melhor) + linha.slice(0, melhor)


## Paredes de colisão (grupo "paredes") ao longo das duas bordas.
func _atualizar_paredes() -> void:
	if _paredes_shape == null:
		var corpo := StaticBody2D.new()
		corpo.name = "Paredes"
		corpo.add_to_group("paredes")
		add_child(corpo)   # sem owner: não é gravado na cena
		_paredes_shape = CollisionShape2D.new()
		corpo.add_child(_paredes_shape)

	var n := centerline.size()
	var segs := PackedVector2Array()
	for i in n:
		var j := (i + 1) % n
		segs.append_array(PackedVector2Array([left_border[i], left_border[j], right_border[i], right_border[j]]))
	var forma := ConcavePolygonShape2D.new()
	forma.segments = segs
	_paredes_shape.shape = forma


func _draw() -> void:
	if centerline.is_empty():
		return
	# Asfalto: dois triângulos por segmento, entre as duas bordas. draw_primitive não
	# triangula, por isso não falha com quadriláteros torcidos nas curvas apertadas
	# (draw_colored_polygon dava "triangulation failed"), e não deixa buracos.
	var n := centerline.size()
	var cor := Color(0.25, 0.25, 0.25)
	var cores := PackedColorArray([cor, cor, cor])
	var sem_uv := PackedVector2Array()
	for i in n:
		var j := (i + 1) % n
		draw_primitive(PackedVector2Array([left_border[i], left_border[j], right_border[j]]), cores, sem_uv)
		draw_primitive(PackedVector2Array([left_border[i], right_border[j], right_border[i]]), cores, sem_uv)
	draw_polyline(_fechada(left_border), Color.WHITE, 3.0, true)
	draw_polyline(_fechada(right_border), Color.WHITE, 3.0, true)

	# Linha de partida
	var t := Vector2.from_angle(start_rotation)
	var normal := Vector2(-t.y, t.x) * largura * 0.5
	draw_line(start_position - normal, start_position + normal, Color.YELLOW, 4.0)


func _fechada(pts: PackedVector2Array) -> PackedVector2Array:
	return pts + PackedVector2Array([pts[0]])
