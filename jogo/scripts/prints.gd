extends Node
## Prints de tela para testes (autoload "Prints"): F12 rodando pelo editor (não no jogo exportado), em qualquer tela, ou o item SCREENSHOT da
## aba DEV do menu de pausa. Salva em user://prints/ (no Windows: %APPDATA%\Godot\app_userdata\Artemis Outpost\prints),
## fora do projeto: não vai para o git nem é importado pelo Godot. A tela de 320x180 é ampliada 4x sem borrar.

signal salvo(caminho: String)

const PASTA := "user://prints"
const ESCALA := 4

var flash: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # funciona com o jogo pausado
	var camada := CanvasLayer.new()
	camada.layer = 100
	add_child(camada)
	flash = ColorRect.new()
	flash.size = Vector2(320, 180)
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(flash)


func _input(ev: InputEvent) -> void:
	if OS.has_feature("editor") and ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_F12:
		tirar()


## Espera o quadro terminar de desenhar, salva e devolve o caminho completo do arquivo.
func tirar() -> String:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() * ESCALA, img.get_height() * ESCALA, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(PASTA)
	var quando := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var caminho := "%s/artemis_%s_%03d.png" % [PASTA, quando, Time.get_ticks_msec() % 1000]
	var completo := ProjectSettings.globalize_path(caminho)
	if img.save_png(caminho) != OK:
		push_error("Não deu para salvar o print em " + completo)
		return ""
	print("print salvo: ", completo)
	flash.color.a = 0.5                              # depois de salvar, para o flash não sair no print
	create_tween().tween_property(flash, "color:a", 0.0, 0.25)
	salvo.emit(completo)
	return completo


func abrir_pasta() -> void:
	DirAccess.make_dir_recursive_absolute(PASTA)
	OS.shell_open(ProjectSettings.globalize_path(PASTA))
