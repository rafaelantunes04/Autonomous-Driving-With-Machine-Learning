extends CanvasLayer
class_name HudCorrida

# CanvasLayer fica fixo no ecrã, independente da câmara.

var _carro: Carro
var _stats: EstatisticasCorrida
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)


func configurar(carro: Carro, stats: EstatisticasCorrida) -> void:
	_carro = carro
	_stats = stats


func _process(_delta: float) -> void:
	if _carro == null or _stats == null:
		return
	var rodas := rad_to_deg(_carro.direcao_rodas)
	var lado := "reta"
	if rodas > 1.0:
		lado = "direita"
	elif rodas < -1.0:
		lado = "esquerda"
	var rumo := fposmod(_carro.rotation_degrees, 360.0)

	_label.text = "Velocidade: %d km/h\nDireção das rodas: %.0f° (%s)\nRumo do carro: %.0f°\n\nTempo: %s\nBatidas: %d\nVoltas: %d | Última: %s | Melhor: %s\n\nR nova pista | Enter reinicia | C câmara" % [
			int(_carro.velocidade_kmh()), absf(rodas), lado, rumo,
			_formatar_tempo(_stats.tempo), _stats.batidas, _stats.voltas,
			_formatar_tempo(_stats.ultima_volta), _formatar_tempo(_stats.melhor_volta)]


func _formatar_tempo(t: float) -> String:
	if t < 0.0:
		return "--:--.---"
	return "%02d:%06.3f" % [int(t / 60.0), fmod(t, 60.0)]
