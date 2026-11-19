extends Node
## Doble de ClienteRed para los tests de espera.gd y partida.gd: mismas señales
## y funciones, sin ENet de verdad. Cada test dispara las señales a mano para
## simular lo que mandaría el servidor.

signal conectado
signal fallo_conexion
signal desconectado_del_servidor
signal sala_actualizada(sala: Dictionary)
signal partida_iniciada(config: Dictionary)
signal estado_actualizado(estado: Dictionary)
signal partida_terminada(resultado: Dictionary)
signal error_recibido(mensaje: String)
## Chat de la partida (PBI-08): un mensaje nuevo, la lista entera al unirse o
## reconectarse, y una denuncia que empieza o se resuelve.
signal chat_recibido(mensaje: Dictionary)
signal chat_reiniciado(mensajes: Array)
signal denuncia_actualizada(denuncia: Dictionary)

var sala_id := ""
var servidor_direccion := "localhost:9000"
var config: Dictionary = {}
var sala: Dictionary = {}
var ultimo_estado: Dictionary = {}
var resultado: Dictionary = {}
var chat: Array = []
var denuncia: Dictionary = {}

## Lista de [nombre_de_funcion, ...argumentos] en el orden en que se llamaron.
var llamadas: Array = []


func preparar(p_sala_id: String, p_servidor_direccion: String) -> void:
	sala_id = p_sala_id
	servidor_direccion = p_servidor_direccion


func conectar_al_servidor() -> void:
	llamadas.append(["conectar_al_servidor"])


func unirse_partida(usuario_id: String, token: String) -> void:
	llamadas.append(["unirse_partida", usuario_id, token])


func empezar_partida() -> void:
	llamadas.append(["empezar_partida"])


func actualizar_sala() -> void:
	llamadas.append(["actualizar_sala"])


func enviar(tipo: String, payload: Dictionary = {}) -> void:
	llamadas.append(["enviar", tipo, payload])


func desconectar() -> void:
	llamadas.append(["desconectar"])
