extends CanvasLayer
class_name HudCorrida

## Emitido quando o jogador clica no botão do painel de resultado.
signal continuar_clicado

## Mostra rumo, ângulo das rodas e sensores do primeiro carro no placar.
@export var mostrar_telemetria: bool = false

const COR_PAINEL := Color(0.055, 0.075, 0.11, 0.94)
const COR_PAINEL_RESULTADO := Color(0.055, 0.075, 0.11, 0.97)
const COR_LINHA := Color(0.12, 0.16, 0.22)
const COR_TEXTO := Color(0.75, 0.79, 0.85)
const COR_TEXTO_FRACO := Color(0.65, 0.69, 0.75)
const COR_DESTAQUE := Color(0.75, 0.58, 1.0)    # melhor volta
const COR_CORRIDA := Color(0.65, 0.80, 1.0)

var _carros: Array[Carro] = []
var _total_voltas: int = 5
var _tempo_limite: float = 270.0
var _total_corridas: int = 10

var _container_carros: VBoxContainer
var _melhor_geral: Label
var _cabecalho_corrida: Label
var _cronometro: Label
var _tempo_decorrido: float = 0.0
var _cronometro_ativo: bool = true
var _regras: Label
var _telemetria: Label

var _overlay_resultado: CenterContainer
var _titulo_resultado: Label
var _detalhe_resultado: Label
var _resumo_resultado: Label
var _botao_continuar: Button

## Uma entrada por carro, com os Labels da sua linha no placar.
var _linhas: Array[Dictionary] = []


func _ready() -> void:
	_criar_interface()


# ------------------------------------------------------------------ API pública

func configurar_corrida(
	carros: Array[Carro],
	total_voltas: int,
	tempo_limite: float = 270.0,
	total_corridas: int = 10
) -> void:
	_carros = carros
	_total_voltas = total_voltas
	_tempo_limite = tempo_limite
	_total_corridas = total_corridas

	atualizar_numero_corrida(1)
	_regras.text = "%d VOLTAS  |  LIMITE %.0f s" % [_total_voltas, _tempo_limite]

	for filho in _container_carros.get_children():
		filho.queue_free()
	_linhas.clear()
	for carro in _carros:
		_criar_linha_carro(carro)


## Atualiza o "01/10" do cabeçalho (usado pelo campeonato de várias corridas).
func atualizar_numero_corrida(numero: int) -> void:
	if _cabecalho_corrida != null:
		_cabecalho_corrida.text = "%02d/%02d" % [numero, _total_corridas]


## Mostra o painel final (fim de corrida ou do teste inteiro).
func mostrar_painel_resultado(titulo: String, detalhe: String, resumo: String, teste_final: bool) -> void:
	_titulo_resultado.text = titulo
	_detalhe_resultado.text = detalhe
	_resumo_resultado.text = resumo
	_botao_continuar.text = "FECHAR TESTE" if teste_final else "CONTINUAR PARA A PRÓXIMA CORRIDA"
	_botao_continuar.show()
	_overlay_resultado.show()


func ocultar_resultado() -> void:
	if _overlay_resultado != null:
		_overlay_resultado.hide()


func reiniciar_cronometro() -> void:
	_tempo_decorrido = 0.0
	_cronometro_ativo = true
	if _cronometro != null:
		_cronometro.text = EstatisticasCorrida.formatar_tempo(0.0)


func parar_cronometro() -> void:
	_cronometro_ativo = false


# ------------------------------------------------------------------ Atualização

func _physics_process(delta: float) -> void:
	if not _cronometro_ativo or _carros.is_empty():
		return

	var corrida := get_parent() as Corrida
	if corrida != null and (corrida.modo_treino or corrida.modo_avaliacao):
		_tempo_decorrido = float(_carros[0].get("rl_tempo_simulado"))
		_cronometro.text = EstatisticasCorrida.formatar_tempo(_tempo_decorrido)
		return
	_tempo_decorrido += delta
	_cronometro.text = EstatisticasCorrida.formatar_tempo(_tempo_decorrido)

	if _tempo_decorrido >= _tempo_limite:
		_cronometro_ativo = false
		_cronometro.text = EstatisticasCorrida.formatar_tempo(_tempo_limite)
		print("Tempo limite da corrida atingido!")


func _process(_delta: float) -> void:
	if _carros.is_empty():
		return
	_atualizar_telemetria()
	for i in _carros.size():
		_atualizar_linha(i)
	_ordenar_linhas()
	_atualizar_melhor_geral()


func _atualizar_telemetria() -> void:
	if _telemetria == null:
		return
	var primeiro := _carros[0]
	_telemetria.text = (
		"TELEMETRIA DO CARRO 1\n"
		+ "Rumo %.0f°  |  Rodas %.0f°\n"
		+ "Sensores (0 perto, 1 longe)\n"
		+ "Frente %.2f\nEsq. %.2f / %.2f  |  Dir. %.2f / %.2f"
	) % [
		primeiro.estado_rumo, primeiro.estado_angulo_rodas, primeiro.estado_sensor_front,
		primeiro.estado_sensor_left, primeiro.estado_sensor_left_2,
		primeiro.estado_sensor_right, primeiro.estado_sensor_right_2
	]


func _atualizar_linha(i: int) -> void:
	var carro := _carros[i]
	var stats := carro.estatisticas
	var linha := _linhas[i]
	linha["progresso"].text = "Volta %d/%d  |  Batidas %d" % [mini(stats.voltas + 1, _total_voltas), _total_voltas, stats.batidas]
	linha["ultima"].text = "Ultima: %s" % EstatisticasCorrida.formatar_tempo(stats.ultima_volta)
	linha["melhor"].text = "Melhor: %s" % EstatisticasCorrida.formatar_tempo(stats.melhor_volta)
	linha["velocidade"].text = "Velocidade: %.0f km/h" % carro.velocidade_kmh


## Ordena o placar por voltas completas (empates mantêm a ordem dos carros).
## Carros com as mesmas voltas partilham a posição.
func _ordenar_linhas() -> void:
	var ordem: Array[int] = []
	for i in _carros.size():
		ordem.append(i)
	ordem.sort_custom(func(a: int, b: int) -> bool:
		var voltas_a := _carros[a].estatisticas.voltas
		var voltas_b := _carros[b].estatisticas.voltas
		return a < b if voltas_a == voltas_b else voltas_a > voltas_b
	)

	var posicao_atual := 1
	for rank in ordem.size():
		var i := ordem[rank]
		if rank > 0 and _carros[i].estatisticas.voltas < _carros[ordem[rank - 1]].estatisticas.voltas:
			posicao_atual = rank + 1
		_linhas[i]["posicao"].text = str(posicao_atual)
		_container_carros.move_child(_linhas[i]["painel"], rank)


func _atualizar_melhor_geral() -> void:
	var melhor_tempo := INF
	var melhor_carro: Carro = null
	for carro in _carros:
		var tempo := carro.estatisticas.melhor_volta
		if tempo >= 0.0 and tempo < melhor_tempo:
			melhor_tempo = tempo
			melhor_carro = carro

	if melhor_carro != null:
		_melhor_geral.text = "%s - %s" % [melhor_carro.nome, EstatisticasCorrida.formatar_tempo(melhor_tempo)]
	else:
		_melhor_geral.text = "Aguardando primeira volta..."


# ------------------------------------------------------------------ Construção da interface

func _novo_label(texto: String, tamanho: int, cor: Color) -> Label:
	var label := Label.new()
	label.text = texto
	label.add_theme_font_size_override("font_size", tamanho)
	label.add_theme_color_override("font_color", cor)
	return label


func _estilo(cor: Color, raio: int) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = cor
	estilo.set_corner_radius_all(raio)
	estilo.content_margin_left = 7
	estilo.content_margin_right = 7
	estilo.content_margin_top = 5
	estilo.content_margin_bottom = 5
	return estilo


func _criar_interface() -> void:
	var painel := PanelContainer.new()
	painel.position = Vector2(12, 12)
	painel.custom_minimum_size = Vector2(230, 0)
	painel.add_theme_stylebox_override("panel", _estilo(COR_PAINEL, 10))
	add_child(painel)

	var principal := VBoxContainer.new()
	principal.add_theme_constant_override("separation", 5)
	painel.add_child(principal)

	var cabecalho := HBoxContainer.new()
	principal.add_child(cabecalho)
	var titulo := _novo_label("CLASSIFICACAO", 15, Color.WHITE)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecalho.add_child(titulo)
	_cabecalho_corrida = _novo_label("01/10", 15, COR_CORRIDA)
	cabecalho.add_child(_cabecalho_corrida)

	_cronometro = _novo_label("00:00.000", 14, Color.YELLOW)
	principal.add_child(_cronometro)
	_regras = _novo_label("5 VOLTAS  |  LIMITE 270 s", 12, COR_TEXTO_FRACO)
	principal.add_child(_regras)

	_container_carros = VBoxContainer.new()
	_container_carros.add_theme_constant_override("separation", 7)
	principal.add_child(_container_carros)

	principal.add_child(HSeparator.new())
	principal.add_child(_novo_label("MELHOR VOLTA GERAL", 12, COR_TEXTO_FRACO))
	_melhor_geral = _novo_label("Aguardando primeira volta...", 14, COR_DESTAQUE)
	principal.add_child(_melhor_geral)

	if mostrar_telemetria:
		principal.add_child(HSeparator.new())
		_telemetria = _novo_label("", 12, COR_TEXTO)
		principal.add_child(_telemetria)

	_criar_painel_resultado()


func _criar_painel_resultado() -> void:
	_overlay_resultado = CenterContainer.new()
	_overlay_resultado.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay_resultado)

	var painel := PanelContainer.new()
	painel.custom_minimum_size = Vector2(520, 320)
	painel.add_theme_stylebox_override("panel", _estilo(COR_PAINEL_RESULTADO, 14))
	_overlay_resultado.add_child(painel)

	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 10)
	painel.add_child(coluna)

	_titulo_resultado = _novo_label_centrado("VITÓRIA!", 28, Color(1.0, 0.82, 0.20), coluna)
	_detalhe_resultado = _novo_label_centrado("", 18, Color.WHITE, coluna)
	_resumo_resultado = _novo_label_centrado("", 14, Color(0.85, 0.88, 0.93), coluna)

	_botao_continuar = Button.new()
	_botao_continuar.custom_minimum_size = Vector2(0, 42)
	_botao_continuar.pressed.connect(func() -> void:
		_botao_continuar.hide()
		continuar_clicado.emit()
	)
	coluna.add_child(_botao_continuar)

	_overlay_resultado.hide()
	_botao_continuar.hide()


func _novo_label_centrado(texto: String, tamanho: int, cor: Color, pai: Node) -> Label:
	var label := _novo_label(texto, tamanho, cor)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pai.add_child(label)
	return label


## Cria a linha de um carro no placar e regista os seus Labels em _linhas.
func _criar_linha_carro(carro: Carro) -> void:
	var painel := PanelContainer.new()
	painel.add_theme_stylebox_override("panel", _estilo(COR_LINHA, 6))
	_container_carros.add_child(painel)

	var horizontal := HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", 9)
	painel.add_child(horizontal)

	var posicao := _novo_label(str(_linhas.size() + 1), 20, Color.WHITE)
	posicao.custom_minimum_size.x = 22
	horizontal.add_child(posicao)

	var barra_cor := ColorRect.new()
	barra_cor.color = carro.cor
	barra_cor.custom_minimum_size = Vector2(4, 0)
	horizontal.add_child(barra_cor)

	var coluna := VBoxContainer.new()
	coluna.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coluna.add_theme_constant_override("separation", 3)
	horizontal.add_child(coluna)
	coluna.add_child(_novo_label(carro.nome, 16, Color.WHITE))

	var linha := {"painel": painel, "posicao": posicao}
	var informacao := {   # chave -> (texto inicial, cor)
		"progresso": ["Volta 1/%d  |  Batidas 0" % _total_voltas, COR_TEXTO],
		"ultima": ["Ultima: --:--.---", COR_TEXTO],
		"melhor": ["Melhor: --:--.---", COR_DESTAQUE],
		"velocidade": ["Velocidade: 0 km/h", COR_TEXTO],
	}
	for chave in informacao:
		var label := _novo_label(informacao[chave][0], 12, informacao[chave][1])
		coluna.add_child(label)
		linha[chave] = label
	_linhas.append(linha)
