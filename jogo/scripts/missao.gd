extends Node
## Estado da missão que continua existindo quando o jogo troca de cena (autoload "Missao").
## Guarda o local de pouso e as condições de partida dele, o dia atual e o histórico de cada dia (para o fim).
## Os outros sistemas (indicadores, dias, eventos) leem daqui: Missao.local_pouso, Missao.condicoes["energia"]...

const ARQUIVO := "res://dados/locais_pouso.json"

var local_pouso := ""                    # "borda", "polo" ou "planicie"; vazio = ainda não escolheu
var dados_local: Dictionary = {}         # a entrada inteira do local no JSON (título, vantagem, risco...)
var condicoes: Dictionary = {}           # as condições de partida do local (energia, oxigênio, noite, gelo...)

var dia := 0                             # 1 a 7; 0 = a missão ainda não começou
## um item por dia: {"dia": 1, "noite": false, "acoes": ["CLEAN THE SOLAR PANELS", ...], "valores": {...}}
## ("valores" = os indicadores depois do fechamento do dia)
var historico: Array = []
var resultado := ""                      # "concluida", "dificuldades" ou "abortada" (vazio = em andamento)
var causa := ""                          # na missão abortada: o indicador que zerou

# erupção solar (ver tempestade.gd e "radiacao" em recursos.json)
var dia_erupcao := 0                     # o dia sorteado da erupção (0 = nenhuma)
var alarme_apos := 1                     # o alarme toca depois desta tarefa do dia (1ª ou 2ª, sorteado)
var evento_solar: Dictionary = {}        # o evento real do DONKI usado como referência (eventos_solares.json)
var blindagem := 0                       # quantas vezes a blindagem foi reforçada
var tempestade: Dictionary = {}          # o que aconteceu: {"dia": 3, "abrigo": true, "dano": 5}; vazio = ainda não

## Tutoriais dos minigames e cards de sala já vistos nesta missão ("minigame/agua", "sala/habitat"). Não fica em
## arquivo: cada missão nova (inclusive o "jogar novamente" e reabrir o jogo) mostra todos de novo.
var tutoriais_vistos: Dictionary = {}


## Relatório final: o que aconteceu de verdade durante a partida (registrado pelo ciclo_dias.gd conforme ocorre).
## um item por acontecimento: {"n": 0, "dia": 3, "tipo": "critico", "titulo": "POWER LOW", "descricao": "...", "impacto": "energia", "peso": 8}
var eventos: Array = []
## a decisão de maior impacto (escolhida no fim por Relatorio.preparar): {"tipo", "titulo", "texto", "tradeoff", "curiosidade", ...}
var decisao_impacto: Dictionary = {}
## Evento da NASA DONKI usado como referência. Vazio = integração pendente.
## Quando existir: {"id": "...", "tipo": "CME", "data": "2026-03-04", "fonte": "ao_vivo" ou "arquivo", "relacao": "texto curto"}
var donki: Dictionary = {}


func escolher_local(id: String) -> void:
	for local in JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO)):
		if local["id"] == id:
			local_pouso = id
			dados_local = local
			condicoes = local["condicoes"]
			print("Missao: pouso em ", id, " ", condicoes)
			return
	push_error("Local de pouso desconhecido: " + id)


## Guarda um acontecimento importante da missão (peso maior = mais chance de entrar na linha do tempo do relatório).
func registrar_evento(dia_ev: int, tipo: String, titulo: String, descricao: String, impacto := "", peso := 1) -> void:
	eventos.append({"n": eventos.size(), "dia": dia_ev, "tipo": tipo, "titulo": titulo, "descricao": descricao,
		"impacto": impacto, "peso": peso})


## Nova missão: volta tudo ao começo (a tela de pouso escolhe o local de novo).
func reiniciar() -> void:
	local_pouso = ""
	dados_local = {}
	condicoes = {}
	dia = 0
	historico = []
	resultado = ""
	causa = ""
	dia_erupcao = 0
	alarme_apos = 1
	evento_solar = {}
	blindagem = 0
	tempestade = {}
	tutoriais_vistos = {}
	eventos = []
	decisao_impacto = {}
	donki = {}

