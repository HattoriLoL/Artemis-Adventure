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
 
## Relatório final: o que aconteceu de verdade durante a partida (registrado pelo ciclo_dias.gd conforme ocorre).
## um item por acontecimento: {"n": 0, "dia": 3, "tipo": "critico", "titulo": "POWER LOW", "descricao": "...", "impacto": "energia", "peso": 8}
var eventos: Array = []
## a decisão de maior impacto (escolhida no fim por Relatorio.preparar): {"tipo", "titulo", "texto", "tradeoff", "curiosidade", ...}
var decisao_impacto: Dictionary = {}
## Resultado científico. Ainda não existe sistema de ciência: o relatório mostra "--" enquanto isto estiver vazio.
## objetivos: [{"nome": "LUNAR ICE INVESTIGATION", "feito": false}, ...]  (vazio = o relatório mostra os 3 padrão como pendentes)
var ciencia := {"amostras": [], "objetivos": [], "dados_transmitidos": 0.0, "dados_totais": 0.0}
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
	eventos = []
	decisao_impacto = {}
	ciencia = {"amostras": [], "objetivos": [], "dados_transmitidos": 0.0, "dados_totais": 0.0}
	donki = {}
 
