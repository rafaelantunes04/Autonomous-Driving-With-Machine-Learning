extends CanvasLayer
class_name HudCorrida

## Emitido quando o jogador clica no botão do painel de resultado.
signal continuar_clicado

## Mostra rumo, ângulo das rodas e sensores do primeiro carro no placar.
@export var mostrar_telemetria: bool = false

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
var _painel_resultado: PanelContainer
var _titulo_resultado: Label
var _detalhe_resultado: Label
var _resumo_resultado: Label
var _botao_continuar: Button

var _linhas: Array[Dictionary] = []


func _ready() -> void:
	_criar_interface()


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

	_cabecalho_corrida.text = "01/%02d" % _total_corridas
	_regras.text = "%d VOLTAS  |  LIMITE %.0f s" % [
		_total_voltas, _tempo_limite
	]

	for filho in _container_carros.get_children():
		filho.queue_free()

	_linhas.clear()

	for i in range(_carros.size()):
		_criar_linha_carro(i)


## Atualiza o "01/10" do cabeçalho (usado pelo campeonato de várias corridas).
func atualizar_numero_corrida(numero: int) -> void:
	if _cabecalho_corrida != null:
		_cabecalho_corrida.text = "%02d/%02d" % [numero, _total_corridas]


## Mostra o painel final (fim de corrida ou do teste inteiro).
func mostrar_painel_resultado(
	titulo: String,
	detalhe: String,
	resumo: String,
	teste_final: bool
) -> void:
	_titulo_resultado.text = titulo
	_detalhe_resultado.text = detalhe
	_resumo_resultado.text = resumo
	_botao_continuar.text = "FECHAR TESTE" if teste_final else "CONTINUAR PARA A PRÓXIMA CORRIDA"
	_botao_continuar.show()
	_overlay_resultado.show()


func ocultar_resultado() -> void:
	if _overlay_resultado != null:
		_overlay_resultado.hide()


func _novo_label(
	texto: String,
	tamanho: int,
	cor: Color
) -> Label:
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

	painel.add_theme_stylebox_override(
		"panel",
		_estilo(Color(0.055, 0.075, 0.11, 0.94), 10)
	)

	add_child(painel)

	var principal := VBoxContainer.new()
	principal.add_theme_constant_override("separation", 5)
	painel.add_child(principal)

	# Cabecalho
	var cabecalho := HBoxContainer.new()
	principal.add_child(cabecalho)

	var titulo := _novo_label(
		"CLASSIFICACAO",
		15,
		Color.WHITE
	)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecalho.add_child(titulo)

	_cabecalho_corrida = _novo_label(
		"01/10",
		15,
		Color(0.65, 0.80, 1.0)
	)
	cabecalho.add_child(_cabecalho_corrida)

	_cronometro = _novo_label(
		"00:00.000",
		14,
		Color.YELLOW
	)

	principal.add_child(_cronometro)

	_regras = _novo_label(
		"5 VOLTAS  |  LIMITE 270 s",
		12,
		Color(0.65, 0.69, 0.75)
	)
	principal.add_child(_regras)

	# Container das classificacoes
	_container_carros = VBoxContainer.new()
	_container_carros.add_theme_constant_override(
		"separation", 7
	)
	principal.add_child(_container_carros)

	# Melhor volta geral
	var separador := HSeparator.new()
	principal.add_child(separador)

	var titulo_melhor := _novo_label(
		"MELHOR VOLTA GERAL",
		12,
		Color(0.65, 0.69, 0.75)
	)
	principal.add_child(titulo_melhor)

	_melhor_geral = _novo_label(
		"Aguardando primeira volta...",
		14,
		Color(0.75, 0.58, 1.0)
	)
	principal.add_child(_melhor_geral)

	if mostrar_telemetria:
		principal.add_child(HSeparator.new())
		_telemetria = _novo_label("", 12, Color(0.75, 0.79, 0.85))
		principal.add_child(_telemetria)

	_criar_painel_resultado()


func _criar_painel_resultado() -> void:
	_overlay_resultado = CenterContainer.new()
	_overlay_resultado.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay_resultado)

	_painel_resultado = PanelContainer.new()
	_painel_resultado.custom_minimum_size = Vector2(520, 320)
	_painel_resultado.add_theme_stylebox_override(
		"panel",
		_estilo(Color(0.055, 0.075, 0.11, 0.97), 14)
	)
	_overlay_resultado.add_child(_painel_resultado)

	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 10)
	_painel_resultado.add_child(coluna)

	_titulo_resultado = _novo_label("VITÓRIA!", 28, Color(1.0, 0.82, 0.20))
	_titulo_resultado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_titulo_resultado)

	_detalhe_resultado = _novo_label("", 18, Color.WHITE)
	_detalhe_resultado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_detalhe_resultado)

	_resumo_resultado = _novo_label("", 14, Color(0.85, 0.88, 0.93))
	_resumo_resultado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_resumo_resultado)

	_botao_continuar = Button.new()
	_botao_continuar.text = "CONTINUAR PARA A PRÓXIMA CORRIDA"
	_botao_continuar.custom_minimum_size = Vector2(0, 42)
	_botao_continuar.pressed.connect(func() -> void:
		_botao_continuar.hide()
		continuar_clicado.emit()
	)
	coluna.add_child(_botao_continuar)

	_overlay_resultado.hide()
	_botao_continuar.hide()


func _criar_linha_carro(i: int) -> void:
	var carro := _carros[i]
	var painel := PanelContainer.new()

	painel.add_theme_stylebox_override(
		"panel",
		_estilo(Color(0.12, 0.16, 0.22), 6)
	)

	_container_carros.add_child(painel)

	var horizontal := HBoxContainer.new()
	horizontal.add_theme_constant_override("separation", 9)
	painel.add_child(horizontal)

	# Posicao na corrida
	var posicao := _novo_label(
		str(i + 1),
		20,
		Color.WHITE
	)
	posicao.custom_minimum_size.x = 22
	horizontal.add_child(posicao)

	# Barra de cor do carro (diretamente do carro)
	var barra := ColorRect.new()
	barra.color = carro.cor
	barra.custom_minimum_size = Vector2(4, 0)
	horizontal.add_child(barra)

	# Informacoes
	var coluna := VBoxContainer.new()
	coluna.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coluna.add_theme_constant_override("separation", 3)
	horizontal.add_child(coluna)

	# Nome diretamente do carro
	var nome := _novo_label(
		carro.nome,
		16,
		Color.WHITE
	)
	coluna.add_child(nome)

	var progresso := _novo_label(
		"Volta 1/5  |  Batidas 0",
		12,
		Color(0.75, 0.79, 0.85)
	)
	coluna.add_child(progresso)

	var ultima := _novo_label(
		"Ultima: --:--.---",
		12,
		Color(0.75, 0.79, 0.85)
	)
	coluna.add_child(ultima)

	var melhor := _novo_label(
		"Melhor: --:--.---",
		12,
		Color(0.75, 0.58, 1.0)
	)
	coluna.add_child(melhor)

	var velocidade := _novo_label(
		"Velocidade: 0 km/h",
		12,
		Color(0.75, 0.79, 0.85)
	)
	coluna.add_child(velocidade)

	_linhas.append({
		"painel": painel,
		"posicao": posicao,
		"progresso": progresso,
		"ultima": ultima,
		"melhor": melhor,
		"velocidade": velocidade
	})


func _process(_delta: float) -> void:
	if _carros.is_empty():
		return

	if _telemetria != null:
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

	var melhor_tempo := INF
	var melhor_carro: Carro = null

	# Atualizar informacoes individuais a partir dos carros
	for i in range(_carros.size()):
		var carro := _carros[i]
		var stats := carro.estatisticas
		var linha: Dictionary = _linhas[i]

		var volta_atual := mini(
			stats.voltas + 1,
			_total_voltas
		)

		linha["progresso"].text = (
			"Volta %d/%d  |  Batidas %d" % [
				volta_atual,
				_total_voltas,
				stats.batidas
			]
		)

		linha["ultima"].text = (
			"Ultima: %s" %
			_formatar_tempo(stats.ultima_volta)
		)

		linha["melhor"].text = (
			"Melhor: %s" %
			_formatar_tempo(stats.melhor_volta)
		)

		linha["velocidade"].text = "Velocidade: %.0f km/h" % carro.velocidade_kmh

		if stats.melhor_volta >= 0.0 and stats.melhor_volta < melhor_tempo:
			melhor_tempo = stats.melhor_volta
			melhor_carro = carro

	# Ordenar por voltas completas consultando diretamente os carros
	var ordem: Array[int] = []

	for i in range(_carros.size()):
		ordem.append(i)

	ordem.sort_custom(
		func(a: int, b: int) -> bool:
			var stats_a := _carros[a].estatisticas
			var stats_b := _carros[b].estatisticas
			if stats_a.voltas == stats_b.voltas:
				return a < b
			return stats_a.voltas > stats_b.voltas
	)

	var posicao_atual := 1

	for rank in range(ordem.size()):
		var i := ordem[rank]

		if rank > 0:
			var anterior := ordem[rank - 1]
			if _carros[i].estatisticas.voltas < _carros[anterior].estatisticas.voltas:
				posicao_atual = rank + 1

		_linhas[i]["posicao"].text = str(posicao_atual)

		_container_carros.move_child(
			_linhas[i]["painel"],
			rank
		)

	# Melhor volta entre todos os carros
	if melhor_carro != null:
		_melhor_geral.text = "%s - %s" % [
			melhor_carro.nome,
			_formatar_tempo(melhor_tempo)
		]
	else:
		_melhor_geral.text = "Aguardando primeira volta..."


func _formatar_tempo(tempo: float) -> String:
	if tempo < 0.0:
		return "--:--.---"

	return "%02d:%06.3f" % [
		int(tempo / 60.0),
		fmod(tempo, 60.0)
	]


func _physics_process(delta: float) -> void:
	if not _cronometro_ativo or _carros.is_empty():
		return

	_tempo_decorrido += delta

	_cronometro.text = _formatar_tempo(_tempo_decorrido)

	if _tempo_decorrido >= _tempo_limite:
		_cronometro_ativo = false
		_cronometro.text = _formatar_tempo(_tempo_limite)
		print("Tempo limite da corrida atingido!")


func reiniciar_cronometro() -> void:
	_tempo_decorrido = 0.0
	_cronometro_ativo = true

	if _cronometro != null:
		_cronometro.text = "00:00.000"


func parar_cronometro() -> void:
	_cronometro_ativo = false
