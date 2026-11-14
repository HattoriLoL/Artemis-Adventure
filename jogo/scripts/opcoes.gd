extends Node
## Opções do jogador (autoload "Opcoes"), guardadas em user://opcoes.cfg e aplicadas ao abrir o jogo.
## Por enquanto só a tela cheia, que também liga e desliga com F11 em qualquer tela.
## A tela cheia é a "sem borda" (WINDOW_MODE_FULLSCREEN): o monitor não troca de resolução e o Alt+Tab é instantâneo.
## Com a escala inteira do projeto, 320x180 vira 6x em 1920x1080; em telas que não são múltiplas sobram faixas escuras.

const ARQUIVO := "user://opcoes.cfg"

var tela_cheia := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # F11 funciona até com o jogo pausado
	var cfg := ConfigFile.new()
	if cfg.load(ARQUIVO) == OK:
		tela_cheia = bool(cfg.get_value("video", "tela_cheia", false))
	_aplicar()


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.physical_keycode == KEY_F11:
		definir_tela_cheia(not tela_cheia)


## Rodando dentro da aba Game do editor (Godot 4.4+), a janela do jogo é do editor e não aceita tela cheia.
## Para testar a tela cheia pelo editor: aba Game > menu de 3 pontos > desmarcar "Embed Game on Next Play".
func pode_tela_cheia() -> bool:
	return not OS.has_feature("embedded_in_editor")


func definir_tela_cheia(valor: bool) -> void:
	if not pode_tela_cheia():
		return                                       # não grava: a escolha salva continua valendo fora do editor
	tela_cheia = valor
	_aplicar()
	var cfg := ConfigFile.new()
	cfg.load(ARQUIVO)                                # mantém outras opções que existirem no arquivo
	cfg.set_value("video", "tela_cheia", tela_cheia)
	cfg.save(ARQUIVO)


func _aplicar() -> void:
	if not pode_tela_cheia():
		return
	var janela := get_window()
	if tela_cheia:
		janela.mode = Window.MODE_FULLSCREEN
	elif janela.mode == Window.MODE_FULLSCREEN or janela.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		janela.mode = Window.MODE_WINDOWED           # só sai da tela cheia; não desfaz uma janela maximizada
