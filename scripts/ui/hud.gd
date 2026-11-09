
extends CanvasLayer
class_name HudCorrida

const NOMES = [
    "Carro 1",
    "Carro 2",
    "Carro 3"
]

const CORES = [
    Color(0.25, 0.59, 1.0),
    Color(0.95, 0.27, 0.30),
    Color(0.20, 0.83, 0.49)
]

var _carros: Array[Carro] = []
var _estatisticas: Array[EstatisticasCorrida] = []

# Nome e cor de cada carro (vêm dos participantes). Se faltarem, usa NOMES / CORES.
var _nomes: Array[String] = []
var _cores: Array[Color] = []

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

var _linhas: Array[Dictionary] = []


func _ready() -> void:
    _criar_interface()


func configurar_corrida(
    carros: Array[Carro],
    estatisticas: Array[EstatisticasCorrida],
    total_voltas: int,
    tempo_limite: float = 270.0,
    total_corridas: int = 10,
    nomes: Array[String] = [],
    cores: Array[Color] = []
) -> void:
    _carros = carros
    _estatisticas = estatisticas
    _total_voltas = total_voltas
    _tempo_limite = tempo_limite
    _total_corridas = total_corridas
    _nomes = nomes
    _cores = cores

    _cabecalho_corrida.text = "01/%02d" % _total_corridas
    _regras.text = "%d VOLTAS  |  LIMITE %.0f s" % [
        _total_voltas, _tempo_limite
    ]

    for filho in _container_carros.get_children():
        filho.queue_free()

    _linhas.clear()

    for i in range(_carros.size()):
        _criar_linha_carro(i)


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


func _criar_linha_carro(i: int) -> void:
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

    # Barra de cor do carro
    var barra := ColorRect.new()
    barra.color = _cor_carro(i)
    barra.custom_minimum_size = Vector2(4, 0)
    horizontal.add_child(barra)

    # Informacoes
    var coluna := VBoxContainer.new()
    coluna.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    coluna.add_theme_constant_override("separation", 3)
    horizontal.add_child(coluna)

    var nome := _novo_label(
        _nome_carro(i),
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

    _linhas.append({
        "painel": painel,
        "posicao": posicao,
        "progresso": progresso,
        "ultima": ultima,
        "melhor": melhor
    })


func _process(_delta: float) -> void:
    if _carros.is_empty():
        return

    var melhor_tempo := INF
    var melhor_carro := -1

    # Atualizar informacoes individuais
    for i in range(_carros.size()):
        var stats := _estatisticas[i]
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

        if stats.melhor_volta >= 0.0:
            if stats.melhor_volta < melhor_tempo:
                melhor_tempo = stats.melhor_volta
                melhor_carro = i

    # Ordenar por voltas completas
    var ordem: Array[int] = []

    for i in range(_carros.size()):
        ordem.append(i)

    ordem.sort_custom(
        func(a: int, b: int) -> bool:
            if _estatisticas[a].voltas == _estatisticas[b].voltas:
                return a < b
            return _estatisticas[a].voltas > _estatisticas[b].voltas
    )

    var posicao_atual := 1

    for rank in range(ordem.size()):
        var i := ordem[rank]

        if rank > 0:
            var anterior := ordem[rank - 1]

            if _estatisticas[i].voltas < _estatisticas[anterior].voltas:
                posicao_atual = rank + 1

        _linhas[i]["posicao"].text = str(posicao_atual)

        _container_carros.move_child(
            _linhas[i]["painel"],
            rank
        )

    # Melhor volta entre todos os carros
    if melhor_carro >= 0:
        _melhor_geral.text = "%s - %s" % [
            _nome_carro(melhor_carro),
            _formatar_tempo(melhor_tempo)
        ]
    else:
        _melhor_geral.text = "Aguardando primeira volta..."


func _nome_carro(i: int) -> String:
    if i < _nomes.size():
        return _nomes[i]
    return NOMES[i % NOMES.size()]


func _cor_carro(i: int) -> Color:
    if i < _cores.size():
        return _cores[i]
    return CORES[i % CORES.size()]


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