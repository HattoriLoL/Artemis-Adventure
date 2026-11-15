extends Node
## Estado da missão que continua existindo quando o jogo troca de cena (autoload "Missao").
## Por enquanto guarda só o local de pouso e as condições de partida dele.
## Os outros sistemas (indicadores, dias, eventos) leem daqui: Missao.local_pouso, Missao.condicoes["energia"]...

const ARQUIVO := "res://dados/locais_pouso.json"

var local_pouso := ""                    # "borda", "polo" ou "planicie"; vazio = ainda não escolheu
var dados_local: Dictionary = {}         # a entrada inteira do local no JSON (título, vantagem, risco...)
var condicoes: Dictionary = {}           # as condições de partida do local (energia, oxigênio, noite, gelo...)


func escolher_local(id: String) -> void:
	for local in JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO)):
		if local["id"] == id:
			local_pouso = id
			dados_local = local
			condicoes = local["condicoes"]
			print("Missao: pouso em ", id, " ", condicoes)
			return
	push_error("Local de pouso desconhecido: " + id)
