extends "res://scripts/tutorial_minigame.gd"
## Card de sala: na primeira vez que o jogador entra em cada sala, aparece por cima do jogo um card no mesmo modelo
## do tutorial dos minigames: a ilustração da sala, as tarefas que se fazem nela ("IN THIS ROOM") e um fato real
## sobre para que ela serve para os astronautas, com a fonte.
## Fatos em dados/salas_fatos.json, pela chave da sala (habitat, energia, suporte, estufa, abrigo). As tarefas vêm
## do JSON da própria sala (menos as de "ocultar"), então a lista acompanha o que estiver na sala.
## Ilustração em assets/cards_salas/<sala>.png (120x80); enquanto ela não existe, usa a arte da sala reduzida.
## Visto fica guardado em user://tutoriais.cfg (seção "salas"); o "SHOW TUTORIALS AGAIN" do menu de pausa zera
## junto com os tutoriais. E, Enter, clique, Esc ou X fecham (e o card não aparece mais).

const ARQUIVO_FATOS := "res://dados/salas_fatos.json"
const PASTA_CARDS := "res://assets/cards_salas/"

static var _fatos := {}

var sala := {}                                   # dados da sala (salas/<sala>.json); quem abre o card preenche
var fundo: Texture2D                             # arte da sala, enquanto o card não tem ilustração própria


static func fatos() -> Dictionary:
	if _fatos.is_empty() and FileAccess.file_exists(ARQUIVO_FATOS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO_FATOS))
		if d is Dictionary:
			_fatos = d
	return _fatos


static func tem_sala(nome: String) -> bool:
	return fatos().has(nome)


static func sala_vista(nome: String) -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(ARQUIVO_VISTOS) == OK and bool(cfg.get_value("salas", nome, false))


static func marcar_sala(nome: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(ARQUIVO_VISTOS)
	cfg.set_value("salas", nome, true)
	cfg.save(ARQUIVO_VISTOS)


func _ready() -> void:
	super._ready()
	rotulo_passos = "IN THIS ROOM"
	texto_acao = " TO CONTINUE"
	texto_voltar = ""
	info = fatos().get(id, {}).duplicate()
	info["titulo"] = str(sala.get("titulo", id.to_upper()))
	var ocultar: Array = info.get("ocultar", [])
	var passos: Array[String] = []
	for item in sala.get("tarefas", []) + sala.get("interacoes", []):
		var texto := str(item.get("texto", ""))
		if texto != "" and not str(item.get("id", "")) in ocultar and not texto in passos:
			passos.append(texto)
	info["passos"] = passos
	var c := PASTA_CARDS + id + ".png"
	arte = load(c) if ResourceLoader.exists(c) else null
	var png := str(sala.get("png", ""))
	if arte == null and png != "" and ResourceLoader.exists(png):
		fundo = load(png)


## Sem a ilustração do card, mostra o meio da arte da sala reduzido para caber na moldura (400x240 -> 360x240 -> 1/3).
func _arte() -> void:
	if arte != null or fundo == null:
		super._arte()
		return
	draw_rect(ARTE.grow(2), PRETO)
	draw_rect(ARTE.grow(1), METAL)
	var tam := fundo.get_size()
	var w := minf(tam.x, tam.y * ARTE.size.x / ARTE.size.y)
	var h := w * ARTE.size.y / ARTE.size.x
	draw_texture_rect_region(fundo, ARTE, Rect2((tam.x - w) / 2.0, (tam.y - h) / 2.0, w, h))
