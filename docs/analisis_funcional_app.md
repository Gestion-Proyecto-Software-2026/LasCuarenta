# Análisis funcional — Cartas Online (Guiñote, Mus, Tute)
## Variante: aplicación nativa de escritorio (Windows/Linux)

**Estado:** borrador vivo — actualizadlo cuando cambie una decisión, no lo dejéis desincronizado del código.
**Relación con la otra variante:** este documento es una copia de `analisis_funcional.md` (variante Web) con los cambios que implica repartir un ejecutable en vez de exportar a navegador. Si el equipo decide definitivamente una de las dos opciones, borrad la otra para no mantener dos fuentes de verdad a la vez.
**Cómo usar este documento:** pegadlo entero al principio de la conversación con vuestro asistente de IA antes de pedirle que implemente una parte concreta, indicando qué PBI o fase os toca. El objetivo es que cualquiera de los 4 —con cualquier IA— construya contra los mismos contratos, en vez de que cada uno invente su propio formato de datos o de mensajes.

Este documento complementa al informe de la Práctica 1 (que fija roles, pila del producto y definición de hecho) y a la estructura de carpetas ya acordada. Aquí se detalla el **cómo**: modelo de datos, contratos de API, protocolo de red y reglas de cada juego.

---

## 1. Resumen del sistema

Plataforma para jugar Guiñote, Mus y Tute. Arquitectura de tres piezas:

- **Cliente**: proyecto Godot (GDScript) exportado a ejecutables nativos (Windows/Linux). Solo pinta lo que el servidor le dice; nunca decide el estado del juego.
- **Backend REST** (Node.js + Express + PostgreSQL): todo lo transaccional — cuentas, lobby, historial, ranking.
- **Servidor de partida** (Godot headless, GDScript): autoridad única sobre el estado de una partida en curso. Habla con los clientes por ENet (UDP) y notifica resultados al backend por HTTP interno.

```
Cliente (Godot nativo) ──HTTP REST──▶ Backend (Node+Express) ──SQL──▶ PostgreSQL
        │
        └────────ENet (UDP)────────▶ Servidor de partida (Godot headless)
                                                    │
                                                    └──HTTP interno──▶ Backend (guardar resultado)
```

---

## 2. Convenciones no negociables

Estas decisiones ya están tomadas. Si vuestra IA propone algo distinto, corregidla contra este documento en lugar de aceptarlo:

| Decisión | Se usa | No se usa | Motivo |
|---|---|---|---|
| Lenguaje del motor de juego | GDScript | C# (por convención de equipo, no por límite técnico) | Ya no hay restricción de exportación a Web; se mantiene GDScript por la experiencia ya acumulada en el equipo. Reabrir esta fila si el equipo decide lo contrario. |
| Peer de red multijugador | `ENetMultiplayerPeer` | `WebSocketMultiplayerPeer` | ENet es el peer por defecto de Godot; al no haber cliente Web no hace falta forzar WebSocket |
| Transporte cliente↔servidor de partida | ENet sobre UDP | — | Suficiente para un juego por turnos; no requiere TLS en este canal (a diferencia del backend REST, que sí va cifrado por las credenciales de login) |
| Estilo de código GDScript | `snake_case` (funciones/variables), `PascalCase` (clases), según [guía oficial de Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) | — | Consistencia entre los módulos de los 3 juegos |
| Estilo de código backend | `camelCase`, formateado con Prettier | ESLint | El equipo simplificó este punto en la Práctica 1 entregada: ya no exige un linter en la Definición de Hecho, solo formateo con Prettier |
| Flujo de ramas | rama por PBI/tarea + PR revisada por otra persona antes de `main` | commits directos a `main` | Ya forma parte de la Definición de Hecho |

**Recordatorio de requisitos no funcionales clave** (fuente de verdad: informe de la Práctica 1 entregado, §4 Definición de Hecho — para el detalle completo consultad ese documento, no lo dupliquéis de memoria):
- Tiempo de respuesta de las acciones de juego: < 500 ms.
- Compatibilidad: Windows 10/11 y una distribución Linux común (p. ej. Ubuntu LTS).
- Cobertura de tests de la lógica de juego: ≥ 60%.
- Mínimo de partidas simultáneas soportadas sin degradación: 5.
- Contraseñas cifradas.

---

## 3. Responsabilidades por carpeta (recordatorio)

- `game/server/`: lógica autoritativa pura. **Ningún script de aquí debe heredar de un nodo visual** (`Node2D`, `Control`, etc.). Si necesita hacerlo, esa lógica está en la carpeta equivocada.
- `game/client/`: solo presentación e input. Nunca decide si una jugada es válida — se lo pregunta al servidor y espera respuesta.
- `game/shared/`: lo que ambos necesitan sin duplicar (definición de carta, constantes de mensajes de red, tipos de datos comunes).
- `backend/`: todo lo transaccional, sin ningún conocimiento de las reglas de los juegos.

---

## 4. Modelo de datos (PostgreSQL)

| Tabla | Campos clave | Notas |
|---|---|---|
| `usuarios` | `id`, `email` (único), `password_hash`, `nombre_visible`, `fecha_registro` | Contraseña siempre cifrada (bcrypt o similar) |
| `salas` | `id`, `juego` (`guinote`/`mus`/`tute`), `estado` (`esperando`/`en_curso`/`finalizada`), `capacidad`, `creador_id` → `usuarios.id`, `fecha_creacion` | |
| `sala_participantes` | `sala_id`, `usuario_id`, `posicion` (0-3), `equipo` (0/1, solo aplica a Guiñote/Tute por parejas) | Tabla puente |
| `partidas` | `id`, `sala_id`, `juego`, `fecha_inicio`, `fecha_fin`, `resultado_json` | Registro histórico de una partida ya terminada |
| `partida_jugadores` | `partida_id`, `usuario_id`, `equipo`, `puntos_obtenidos`, `gano` (booleano) | Base para historial (PBI-06) y ranking (PBI-07) |

El **ranking** (PBI-07) se calcula agregando `partida_jugadores` — no hace falta tabla propia salvo que el rendimiento lo justifique más adelante.

---

## 5. Contrato de la API REST (backend)

Prefijo común: `/api`. Autenticación por JWT en cabecera `Authorization: Bearer <token>` salvo donde se indique.

### Autenticación (PBI-01)
| Método | Ruta | Body | Respuesta |
|---|---|---|---|
| POST | `/auth/registro` | `{ email, password, nombre_visible }` | `201 { id, email, nombre_visible }` |
| POST | `/auth/login` | `{ email, password }` | `200 { token, usuario: { id, email, nombre_visible } }` |

### Lobby y salas (PBI-02, PBI-09)
| Método | Ruta | Body | Respuesta |
|---|---|---|---|
| GET | `/salas?juego=guinote` | — | `200 [{ id, juego, estado, jugadores_actuales, capacidad, creador_id }]` |
| POST | `/salas` | `{ juego }` | `201 { id, juego, estado, capacidad, servidor_direccion }` |
| POST | `/salas/:id/unirse` | — | `200 { sala actualizada }` |
| POST | `/salas/:id/expulsar` | `{ usuario_id }` | `200` — solo el creador puede invocarlo |

`servidor_direccion` es la IP/host y puerto (`host:puerto`) a la que el cliente debe conectarse por ENet una vez la sala está completa. La decide el backend a partir de la variable de entorno `GAME_SERVER_ADDRESS` (p. ej. `juego.tudominio.com:9000`): de momento hay un único proceso de servidor de partida que aloja todas las salas, suficiente para el mínimo de 5 partidas simultáneas (§2). Si más adelante hay varias instancias, este es el único punto que cambia.

### Historial y ranking (PBI-06, PBI-07)
| Método | Ruta | Respuesta |
|---|---|---|
| GET | `/usuarios/:id/historial` | `200 [{ partida_id, juego, fecha, resultado, gano }]` |
| GET | `/ranking?juego=guinote` | `200 [{ usuario_id, nombre_visible, puntos_totales, posicion }]` |

### Interno (solo lo llama el servidor de partida, con secreto compartido servidor-a-servidor, nunca el cliente)
| Método | Ruta | Cabecera | Body |
|---|---|---|---|
| GET | `/interno/salas/:id` | `X-Internal-Secret: <INTERNAL_API_SECRET>` | — |
| POST | `/interno/partidas` | `X-Internal-Secret: <INTERNAL_API_SECRET>` | `{ sala_id, jugadores: [{ usuario_id, posicion, equipo }], resultado: { equipo_ganador, puntos_por_equipo, ... } }` |

En `POST /interno/partidas`, `resultado` es lo que devuelve `calcular_resultado` del motor (§7) y `equipo` es `posicion % 2`; con eso el backend puede rellenar `partidas` y `partida_jugadores` (`gano` = el equipo del jugador es `equipo_ganador`). Si el backend no responde, el servidor de partida registra el error en su log; de momento no reintenta.

`GET /interno/salas/:id` es como el servidor de partida se entera de una sala: lo llama la primera vez que un jugador envía `unirse_partida` para esa sala (§6). Responde `200 { id, juego, estado, capacidad, participantes: [{ usuario_id, posicion, equipo }] }` o `404` si la sala no existe. La comunicación siempre va del servidor de partida al backend; el backend nunca llama al servidor de partida.

El backend rechaza con `401` cualquier petición a `/interno/*` cuya cabecera `X-Internal-Secret` no coincida con la variable de entorno `INTERNAL_API_SECRET` (definida en `backend/.env.example` y en `docker-compose.yml`). El servidor de partida debe leer el mismo valor de su propia configuración — no es JWT de usuario, es un secreto fijo compartido entre los dos procesos.

---

## 6. Protocolo en tiempo real (cliente ↔ servidor de partida)

Mensajes sobre ENet (UDP) con formato `{ tipo, payload }` (`payload` siempre es un diccionario, aunque esté vacío). Todos viajan por un único RPC del autoload `CanalRed` (`game/shared/canal_red.gd`), que existe con la misma ruta en cliente y servidor: `CanalRed.enviar(peer_id, mensaje)` para enviar y la señal `CanalRed.mensaje_recibido(peer_id, mensaje)` para recibir. Los nombres de los mensajes están en `MensajesRed` (`game/shared/mensajes_red.gd`). El cliente envía siempre al peer `1` (el servidor) y debe ignorar lo que venga de cualquier otro peer.

**Cliente → Servidor**

| Mensaje | Payload | Cuándo |
|---|---|---|
| `unirse_partida` | `{ usuario_id, token, sala_id }` | Al conectar por ENet |
| `jugar_carta` | `{ carta_id }` | Turno del jugador |
| `cantar` | `{ palo }` (`oros`, `copas`, `espadas` o `bastos`) | Guiñote/Tute: cuando la pareja del jugador acaba de ganar la baza (ver §8) |
| `cantar_tute` | `{ figura }` (`reyes` o `sotas` en Guiñote) | Guiñote/Tute: con las 4 figuras en la mano, en el mismo momento en que se puede cantar |
| `mus` / `no_mus` | — | Fase de decisión en Mus |
| `apostar` | `{ tipo, cantidad }` | Envite/órdago en Mus |
| `chat_enviar` | `{ mensaje }` | PBI-08, en cualquier momento de la partida |

**Servidor → Cliente**

| Mensaje | Payload | Cuándo |
|---|---|---|
| `partida_iniciada` | `{ config: { sala_id, juego, tu_posicion, jugadores: [{ usuario_id, posicion, equipo }] } }` | Al conectarse todos los jugadores de la sala, o al reconectarse uno |
| `estado_partida` | snapshot filtrado (ver §7) | Tras cada acción válida |
| `partida_terminada` | `{ resultado }` | Al finalizar |
| `chat_mensaje` | `{ usuario_id, mensaje }` | PBI-08, al recibir un `chat_enviar` válido de cualquier jugador de la sala |
| `error` | `{ mensaje }` | Jugada inválida, turno equivocado, etc. |

**Validación de `unirse_partida`:** el servidor de partida verifica el JWT él mismo, con el mismo `JWT_SECRET` que el backend (sin preguntar al backend en cada conexión). El token lo firma el backend en el login con el `id` del usuario en su payload; si ese `id` no coincide con `usuario_id`, o el token es inválido o ha caducado, responde `error` y cierra la conexión. Después consulta la sala con `GET /interno/salas/:id` (§5) —solo la primera vez; luego la mantiene en memoria— y comprueba que el usuario es participante y que la sala no está `finalizada`. Cuando todos los participantes se han unido, envía `partida_iniciada` a todos.

**Errores y expulsión:** el servidor responde `error { mensaje }` a cualquier mensaje que no pueda atender, con un texto pensado para mostrarse al jugador. Si el problema impide seguir (token no válido, sala inexistente o terminada, usuario que no es de la sala, juego no disponible), además cierra la conexión un segundo después, para que el cliente llegue a recibir el `error`.

**Desconexión y reconexión:** si un jugador se desconecta, su asiento queda libre pero la partida sigue en memoria. Si vuelve a enviar `unirse_partida` para la misma sala (desde la misma o desde otra conexión), recupera su asiento y recibe `partida_iniciada` y `estado_partida` para ponerse al día. Si el mismo usuario se une desde una segunda conexión mientras la primera sigue abierta, se expulsa la primera. *Pendiente de decidir:* qué pasa si un jugador no vuelve (hoy la partida espera indefinidamente) y cuánto tiempo se espera a que alguien envíe `unirse_partida` tras conectarse.

**Identificador de carta (`carta_id`):** `"<palo>_<valor>"` en minúsculas, con palo `oros|copas|espadas|bastos` y valor `1`–`7`, `10` (sota), `11` (caballo) o `12` (rey). Ejemplos: `"oros_1"`, `"espadas_12"`. Lo genera y valida `Carta` (`game/shared/carta.gd`); un id que no corresponde a ninguna carta se rechaza con `error`.

**Regla importante:** el servidor nunca envía a un cliente las cartas en mano de otro jugador. El snapshot se filtra por destinatario antes de enviarse (ver `vista_para_jugador` en §7).

---

## 7. Interfaz común del motor de reglas

Contrato que debe implementar cada módulo de juego (`guinote/`, `mus/`, `tute/`) dentro de `game/server/game_engine/`. Es el punto más importante de todo el documento: si esto queda mal diseñado pensando solo en Guiñote, Mus y Tute cuestan mucho más de lo necesario.

Implementado en `game/server/game_engine/motor_de_juego.gd` (clase abstracta), junto con `estado_partida.gd` y `resultado_jugada.gd`:

```gdscript
@abstract class_name MotorDeJuego

func _init(p_rng: RandomNumberGenerator = null)  # null = semilla aleatoria; los tests pasan una fija

@abstract func jugadores_admitidos() -> Array[int]  # p. ej. [4], o [2, 4] en Mus

func iniciar(num_jugadores: int) -> EstadoPartida
    # comprueba num_jugadores y llama a _iniciar(): repartir, decidir quién empieza, etc.

@abstract func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array[Dictionary]
    # lo que este jugador puede hacer ahora mismo ([] si nada)

func aplicar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> ResultadoJugada
    # valida y aplica sobre una copia; si no es válida devuelve ok = false con el motivo

@abstract func ha_terminado(estado: EstadoPartida) -> bool

@abstract func calcular_resultado(estado: EstadoPartida) -> Dictionary
    # { equipo_ganador: int, puntos_por_equipo: Array[int] } + lo que cada juego quiera añadir

@abstract func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary
    # oculta las cartas de los demás antes de enviar al cliente
```

Cada juego hereda de `MotorDeJuego` e implementa además `_iniciar(num_jugadores)` y `_ejecutar_jugada(estado, jugador_id, jugada)`, y define su propio estado heredando de `EstadoPartida` (p. ej. `EstadoGuinote`).

**Decisiones del contrato:**
- **`jugador_id` es la posición en la mesa** (`0` … `num_jugadores - 1`), la misma que `sala_participantes.posicion`. El motor no sabe nada de usuarios ni de conexiones: `RoomManager` traduce `usuario_id` ↔ posición ↔ peer de ENet.
- **Equipos por posición:** `MotorDeJuego.equipo_de(jugador_id)` = `jugador_id % 2`, así que en las mesas de 4 las parejas son 0-2 contra 1-3 (§8, §10), y en Mus a 2 cada jugador es su propio equipo. En Mus, el sorteo de parejas (§9) lo resuelve quien asigna los asientos, no el motor.
- **Formato de una jugada:** `{ tipo, ...payload }` con los nombres de los mensajes de §6. Por ejemplo, `{ tipo: "jugar_carta", carta_id: "oros_1" }` o `{ tipo: "cantar", palo: "copas" }`. `RoomManager` convierte el mensaje de red a este formato.
- **La validación la hace la clase base, no cada juego:** `aplicar_jugada` rechaza la jugada si la partida ha terminado o si no está exactamente en `jugadas_validas(...)` (un campo de más o de menos también la invalida), así ningún juego puede olvidarse de validar. Un juego con jugadas imposibles de enumerar puede sobrescribir `_validar()`.
- **No hay turno genérico:** hay jugadas fuera de turno (cantes en Guiñote, decisiones de Mus), así que cada juego expresa el turno a través de `jugadas_validas`.
- **Errores sin excepciones:** GDScript no las tiene. Una jugada inválida devuelve `ResultadoJugada` con `ok = false` y un `error` legible, que el servidor reenvía tal cual en el mensaje `error` de §6. El `estado` recibido nunca se modifica: el motor trabaja sobre `estado.duplicar()`.
- **Aleatoriedad inyectada:** el reparto usa el `RandomNumberGenerator` del motor, así una partida con la misma semilla es reproducible en los tests.

`RoomManager` (en `game/server/room_manager.gd`) no conoce las reglas de ningún juego concreto — solo sabe hablar contra esta interfaz. Añadir un juego nuevo no debería tocar ni una línea de `room_manager.gd`.

---

## 8. Reglas funcionales — Guiñote (PBI-03, prioridad alta)

**⚠️ Corrección de reglas (23/09/2026):** esta sección se reescribe por completo. La fuente usada originalmente para redactarla tenía mal el reparto y la primera mitad de la partida, y se ha sustituido por el "Reglamento Oficial del Torneo de Guiñote Cuatro Vs Cuatro" (Alberto Planas Torrea). Si alguna IA o miembro del equipo ya tenía código escrito contra la versión anterior de esta sección — en particular cualquier cosa que asuma que se reparten 10 cartas de golpe y que no hay fase de robo — **hay que revisarlo**, porque el reparto real y la primera mitad de la partida funcionan de otra forma.

**Jugadores y disposición.** 4 jugadores en 2 parejas, sentados en cruz y enfrentados entre sí (0-2 vs 1-3).

**Baraja, orden y valor de las cartas.** Española de 40 cartas (sin comodines). De mayor a menor: **As, Tres, Rey, Sota, Caballo**, Siete, Seis, Cinco, Cuatro, Dos. Las cartas del palo de triunfo ganan siempre a cualquier carta de otro palo, sea cual sea su rango.

| Carta | Valor |
|---|---|
| As | 11 |
| Tres | 10 |
| Rey | 4 |
| Sota | 3 |
| Caballo | 2 |
| Resto (7, 6, 5, 4, 2) | 0 |

As y Tres se llaman conjuntamente "guiñotes"; Rey, Caballo y Sota son las "figuras" (Rey+Sota en concreto son además las cartas de cante, ver más abajo).

⚠️ **Aviso al implementar (sin cambios):** en Guiñote la **Sota vale más que el Caballo** (en orden y en puntos) — al revés que en el Tute (§10). Si el motor de reglas comparte alguna tabla de valores entre los dos juegos, hay que parametrizarla por juego.

**Reparto y corte.** Para la primera partida del encuentro se sortea quién reparte, de forma equitativa. El dador baraja sin dejar ver las cartas y ofrece la baraja a cortar al jugador de su izquierda. Reparte **6 cartas a cada jugador, en dos tandas de 3**, empezando por el jugador a su derecha y en sentido antihorario. La siguiente carta se coloca boca arriba y en cruz bajo el resto del mazo (que queda en el centro): esa carta marca el **palo de triunfo** de la partida. Antes de la primera baza, las parejas acuerdan quién de cada una recoge las bazas ganadas por su pareja. En partidas siguientes del mismo encuentro (nuevas idas o una vuelta), reparte quien ganó la última baza de la fase anterior con la carta de más fuerza; cualquier jugador de la pareja que no reparte puede barajar antes que el dador.

**Turno y fase de robo (bazas 1 a 4 — "bazas con robada").** La fase de idas tiene **10 bazas en total**: las 4 primeras son "con robada" y las 6 últimas son "de arrastre" (ver más abajo). Empieza el jugador a la derecha del dador; el turno avanza en sentido antihorario en todas las bazas. En estas 4 primeras bazas **cada jugador puede jugar cualquier carta de su mano libremente**, sin obligación de asistir al palo de salida. Gana la baza el triunfo más alto jugado; si nadie jugó triunfo, gana la carta más alta **del palo de salida** (las cartas de los otros dos palos no cuentan para ganar la baza aunque tengan más rango, porque solo compite entre sí el palo que abrió esa baza en concreto). Quien gana la baza se la lleva boca abajo.

Después de cada una de estas 4 bazas, todos los jugadores roban una carta del mazo para volver a tener 6 en la mano: primero roba quien jugó la carta ganadora de la baza, y después los demás por turno, en sentido antihorario. Una vez jugada una carta no se puede cambiar; cada jugador debe incorporar su carta robada a la mano antes de que le vuelva a tocar jugar. La carta que marcaba la pinta se roba en último lugar, por quien le corresponda por turno de robo.

**Fase de arrastre (bazas 5 a 10).** Cuando se agota el mazo, cambian las obligaciones: quien abre la baza juega libremente, pero cada uno de los siguientes debe, en este orden:
1. **Asistir** al palo de salida si lo tiene, y si puede, **montar** (superar la carta más alta jugada de ese palo).
2. Si no tiene el palo de salida, **fallar** (jugar triunfo) solo si tiene triunfo y ese triunfo puede superar cualquier triunfo ya jugado en la baza por un rival.
3. Si tiene el palo de salida pero ya hay un triunfo jugado en la baza, la obligación de montar desaparece (puede asistir con cualquier carta de ese palo).
4. En cualquier otro caso, juega libremente.

Una vez jugada una carta no se puede cambiar, salvo renuncio reconocido y que la pareja contraria permita rectificar (ver "Penalizaciones" más abajo).

**Cantes (acuses).** Un jugador que tenga en la mano la Sota y el Rey del mismo palo puede cantarlos ("veinte en [palo]", o "las cuarenta" si es el palo de triunfo), pero **solo si su pareja acaba de ganar la última baza jugada**. Se puede cantar antes, durante o después de robar, e incluso tras haber salido con la primera carta de la baza siguiente — pero nunca después de que un rival haya jugado ya una carta en esa baza. Si se canta antes de robar la última carta de la fase de robo hay que enseñar las dos cartas juntas; si se canta más tarde, enseñarlas es opcional (salvo en vueltas, donde es obligatorio). Vale **40 puntos** en triunfo, **20 puntos** en cualquier otro palo; una misma pareja puede cantar varias veces a lo largo de la partida (un cante por miembro y por baza ganada). Para llevar la cuenta se puede dejar boca arriba, como recordatorio, una carta cualquiera de la pila de bazas ganadas (preferiblemente una "blanca" que no sea de triunfo) — este recordatorio no se usa para las cuarenta.

**Cambiar el siete de triunfo.** Si un jugador tiene en la mano el 7 del palo de triunfo, puede cambiarlo por la carta que marca la pinta, pero **solo si su pareja ganó la última baza jugada**. Puede hacerse antes, durante o después de robar, pero nunca después de que se haya jugado ya otra baza más adelante. Si no se cambia dentro de las 3 primeras robadas del jugador y, por el orden de robo, la pinta le tocaría robar al compañero en vez de a él, se pierde el derecho a cambiarla. En cualquier caso, en cuanto un jugador ha robado su 4ª carta de la fase de robo, ya no puede hacer el cambio.

**Fin de la fase de idas y tanteo.** Se juegan siempre las 10 bazas completas (las 40 cartas se reparten enteras, aunque una pareja ya haya superado los 100 tantos antes de terminar). Puntúan: el valor de las cartas de las bazas ganadas + los cantes + **10 puntos extra** para quien gane la última baza de las idas ("las diez últimas"). Los puntos de cartas de las idas (sin contar cantes) deben sumar siempre 130 entre las dos parejas; si no cuadra y ambas parejas están de acuerdo en que debería, se repite el reparto.

**Formas de ganar la partida:**
1. **Cantar Tute** — reunir en la mano **las 4 sotas** o **los 4 reyes**: gana la partida al instante, sin importar el tanteo. *(En Guiñote el Tute es de sotas o reyes; en el Tute, §10, es de caballos o reyes — no reutilizar la misma constante entre los dos motores de reglas.)*
2. **Superar los 100 tantos.** Si al terminar las idas solo una pareja supera los 100, esa pareja gana la partida. Si **ambas** superan los 100, gana la pareja que hizo la última baza de las idas, **siempre que esa pareja haya sumado al menos 30 tantos solo por valor de cartas (sin contar cantes)**, en caso de que una pareja no alcance los 30 tantos sin cantes dicha pareja pierde directamente la partida. 
3. **Vueltas.** Si nadie supera los 100 en las idas, se juega una vuelta: es la **misma partida** que continúa (no una partida nueva ni un tanteo a cero) — se reparte de nuevo, pero el tanteo de las idas se lleva de memoria y se le suma el de la vuelta. La vuelta sigue la misma estructura de bazas con robada + arrastre que las idas, aunque el número de bazas puede variar según cuántos tantos queden por resolver. La vuelta termina en cuanto una pareja, llevando bien la cuenta, supera los 100 tantos acumulados **y además gana la última baza jugada**.

*(Nota de terminología, informativa: el reglamento agrupa los tantos en "malas" (los primeros 50) y "buenas" (el resto), y se suele hablar de "ganar de buenas" al superar los 50 en la segunda mitad. No afecta a la lógica de `calcular_resultado` descrita arriba, pero puede aparecer en el marcador o los mensajes de la interfaz si el equipo quiere ser fiel a la jerga real del juego.)*

**Fin de partido (encuentro).** El reglamento oficial encadena varias partidas dentro de un mismo encuentro hasta que una pareja gane el número de partidas acordado. **Decisión de equipo (reformulada tras esta corrección): el encuentro implementado consta de una única partida** — ganarla (por Tute o por tantos, con el desempate de arriba) termina el encuentro completo en la aplicación. *(Esto sustituye a la redacción anterior de este documento, "se juega a una sola mano": ese término no corresponde a ningún concepto real del reglamento — la unidad correcta es la partida, no la "mano".)*

**Penalizaciones (renuncio).** Se considera renuncio, entre otros casos: no asistir, montar o fallar en la fase de arrastre pudiendo hacerlo, en ese orden de obligación; cantar o cambiar el siete sin cumplir las condiciones de arriba; jugar fuera de turno; enseñar cartas propias o mirar las ajenas; o cualquier señal (verbal o gestual) entre compañeros más allá de lo que ya es visible en la mesa. *(El reglamento dedica un apartado extenso a catalogar expresiones verbales prohibidas entre compañeros en partida presencial — no aplica directamente aquí porque el cliente no ofrece ningún canal de voz o chat libre entre compañeros durante la jugada; si en el futuro PBI-08 añadiera chat de equipo también durante la partida en curso, habría que revisar si conviene restringirlo por este motivo.)* Un renuncio hace normalmente perder la partida a quien lo comete; si se usó para evitar una derrota segura, se pierde el encuentro completo. La pareja perjudicada puede optar en su lugar por repetir la fase en la que ocurrió el renuncio.

**Notas de implementación (`game/server/game_engine/guinote/`).** Cómo se traduce lo anterior al motor:
- **Asientos y sentido de juego:** los asientos se numeran en el orden en que se juega (antihorario). "A la derecha" de `p` es `(p + 1) % 4` y "a la izquierda", `(p + 3) % 4`; las parejas quedan 0-2 contra 1-3, como en §7.
- **Reparto:** el dador se sortea con el generador aleatorio del motor. No hay corte: con la baraja mezclada al azar no cambia nada.
- **Robo automático:** al cerrarse cada una de las 4 primeras bazas, el servidor reparte la carta de cada jugador en el orden de robo (el ganador primero); nadie tiene que pedirla. La pinta la roba el último al que le toque en la 4ª baza.
- **Arrastre, cómo se interpretan las obligaciones:** el texto de arriba deja dos puntos abiertos, y el motor los resuelve así (⚠️ pendiente de que el equipo lo confirme; si se decide otra cosa, solo cambia `cartas_permitidas_en_arrastre`):
  - La regla 3 ("si ya hay un triunfo jugado, desaparece la obligación de montar") solo se aplica cuando el palo de salida **no** es triunfo, es decir, cuando alguien ha fallado. Si sale triunfo, hay que montar en triunfo como en cualquier otro palo; si no, al haber siempre un triunfo en la mesa (el de salida), nunca habría que montar en triunfo.
  - No hay excepción por ir ganando el compañero. Hay que montar aunque la carta más alta sea suya, y para fallar solo cuentan los triunfos de los **rivales**: si solo ha fallado el compañero, hay que fallar igualmente, con cualquier triunfo.
- **Cantes:** se pueden hacer fuera de turno y no cambian el turno. El momento para cantar va desde que la pareja gana la baza hasta que un rival juega carta en la siguiente, así que quien sale puede cantar antes o después de echar su carta. Cantar ya revela que se tienen la Sota y el Rey, así que "enseñar las cartas" no requiere nada más. Dos puntos que el texto no dice y el motor decide (⚠️ pendiente de confirmar): un palo ya cantado no se puede volver a cantar en la misma partida, y el **Tute** se canta en el mismo momento que los cantes (tras ganar baza su pareja), no en cualquier momento.
- **Cambio del siete:** ⚠️ todavía no implementado, pendiente de decidir cómo encaja con el robo automático; ver `pbi-03-cantes`.
- **Renuncio:** online no se puede cometer. El servidor solo acepta jugadas válidas y rechaza las demás con un `error`, así que las penalizaciones de renuncio no se implementan.
- **Estado por subtareas:** el reparto, las bazas con robada (`pbi-03-reparto-y-robo`), el arrastre (`pbi-03-fase-arrastre`) y los cantes con el Tute (`pbi-03-cantes`) están implementados. Falta el cambio del siete y el tanteo con las vueltas (`pbi-03-tanteo-y-fin-partida`). `calcular_resultado` ya separa `puntos_cartas` (con las diez últimas) de `puntos_cantes`, que es lo que necesita la regla de los 30 tantos sin cantes. Hasta que estén todas, el motor no se registra en `MOTORES` de `main_server.gd`.

---

## 9. Reglas funcionales — Mus (PBI-04, prioridad media)

Basado en las reglas oficiales aportadas por el equipo, que describen expresamente la variante de **4 jugadores por parejas** como la de referencia; es la que cubre esta sección. La variante a 2 jugadores (ya contemplada en el criterio de aceptación de PBI-04) se deduce quitando la noción de pareja — cada jugador compara sus jugadas de forma individual, sin señas ni agregación de compañero — pero conviene confirmarlo con el equipo antes de implementarla si surge alguna duda de detalle.

**Objetivo.** Una partida son **3 juegos completos** (al mejor de 3); cada juego completo se gana alcanzando **8 amarrakos (40 piedras)** — o, como variante más corta, 6 amarrakos/30 piedras. 1 amarrako = 5 piedras.

**Baraja y valor comparativo.** Española de 40 cartas, sin triunfo ni distinción de palos. Orden de mayor a menor: **Rey = Tres**, Caballo, Sota, Siete, Seis, Cinco, Cuatro, **Dos = As**. Para la jugada de Juego/Punto, valor de cada carta: Rey, Tres, Caballo y Sota = 10 puntos cada una; el resto, su valor natural, excepto Dos y As que valen 1. *(El reglamento contempla también una variante donde solo los 4 Reyes y los 4 Ases cuentan como cartas "altas/bajas", y Tres/Doses conservan su valor natural — no es la variante por defecto; anotar aquí si el equipo prefiere activarla.)*

**Disposición.** Cada jugador saca una carta: las dos cartas más altas forman pareja contra las dos más bajas. Quien sacó la carta más alta es "mano" y se sienta con su compañero enfrente; a su derecha se sienta el rival que sacó la segunda carta más alta.

**Reparto.** El jugador a la izquierda del "mano" baraja y da a cortar a su izquierda (deben quedar al menos 3 cartas en cada montón). Se reparten 4 cartas a cada jugador, de una en una, empezando por el "mano", en sentido derecha-izquierda.

**Fase de Mus.** Tras ver sus 4 cartas, cada jugador dice, en su turno, "Mus" (quiere descartar) o "No hay mus" (juega con estas 4 cartas). En cuanto un jugador dice "No hay mus", se corta el Mus para todos y empieza el juego con las cartas actuales. Si todos piden Mus, cada uno descarta (hasta las 4 cartas) por turno, empezando por el "mano", y el dador reparte las cartas que faltan; el descarte puede repetirse cuantas veces todos quieran seguir pidiendo Mus. Si se agota el mazo a mitad de un reparto, se barajan juntos los descartes de todos (salvo que solo falte completar la mano de un jugador, cuyo descarte se mantiene aparte).

*Caso especial (primera mano de cada juego parcial):* en vez de decir "Mus", cada jugador que lo desee coloca la baraja a su derecha; si nadie corta el Mus así, el "mano" anterior pasa a repartir, y quien cortó el Mus es el nuevo "mano". Si el dador revela una carta sin querer al repartir, hay "Mus visto" obligatorio (cualquiera puede plantarse con sus cartas sin descartar).

**Jugadas, en el orden en que se anuncian:**

| Jugada | Consiste en | Quién puede envidar |
|---|---|---|
| Grande | Tener las cartas más altas posibles | Todos |
| Chica | Tener las cartas más bajas posibles | Todos |
| Pares | Par (2 iguales), Medias (3 iguales) o Duples (2 pares) | Solo si al menos un jugador de cada pareja tiene pares |
| Juego | Suma de las 4 cartas ≥ 31 (mejor: 31, luego 32, salta a 40 y baja: 37, 36, 35, 34, 33) | Solo si al menos un jugador tiene Juego |
| Punto | Si nadie tiene Juego, se compara la suma sin llegar a 31 (mejor: 30, peor: 4) | Sustituye a Juego cuando nadie lo tiene |

El "mano" habla primero en cada jugada, en este orden fijo: Grande → Chica → Pares → Juego (sí/no). Cada jugador, en su turno, puede: **pasar** (sin quedar eliminado, mientras nadie anterior haya envidado), **envidar** (apostar 2 piedras, "envido"), **igualar/subir** ("y yo", o reenvite al doble), **aceptar** ("quiero"), **rechazar** ("no quiero") o ir al **órdago** (apostar el juego completo de 8 amarrakos). Si un jugador pasa después de que otro ya envidó, queda eliminado de esa jugada concreta (no de la mano entera).

**Señas.** En el Mus presencial los compañeros se comunican su jugada mediante gestos discretos que los rivales no perciben (morderse el labio inferior = 2 reyes para Grande, sacar la punta de la lengua = 2 ases para Chica, etc. — es lo que hace del Mus un juego de "farol" en pareja). Es un mecanismo físico de mesa sin equivalente directo en software. **Decisión de equipo: no se implementan señas en la versión online.** Cada pareja se coordina, si quiere, por un canal ajeno al juego (de palabra, presencialmente o por otra app), igual que ya ocurre en otras plataformas de Mus online.

**Cobro de las jugadas, al final de cada juego parcial:**
- **Grande/Chica:** si todos pasan, quien tenga la mejor jugada se lleva 1 piedra (cada una de las dos, de forma independiente). Si alguien envida y nadie acepta, ese jugador se lleva 1 piedra de "deje" en el acto (no hace falta mostrar cartas).
- **Pares/Juego(sí):** si todos pasan, el mejor se lleva el valor de su jugada, sumado al de su compañero si este también tenía pares/juego. Si alguien envida y nadie acepta, se lleva 1 piedra de "deje" en el acto, y además el valor de su jugada + la de su compañero al final, **aunque sus cartas resultasen peores** que las de algún rival.
- **Juego no (Punto):** igual mecánica que Pares, pero solo se cobra 1 piedra.
- Quien rechaza un envite ("no quiero") pierde el derecho a cobrar esa jugada aunque sus cartas fueran mejores al mostrarlas. Las cartas del compañero con mejor jugada siempre cuentan para la pareja, aunque quien apostó tuviera peores cartas. Una piedra olvidada se pierde en cuanto se corta la baraja para la siguiente mano.

**Valor de cada jugada en piedras:**

| Jugada | Piedras |
|---|---|
| El "no" o deje | 1 |
| Grande en paso | 1 |
| Chica en paso | 1 |
| Par | 1 |
| Medias | 2 |
| Duples | 3 |
| Juego | 2 |
| Juego de 31 | 3 |
| Juego no / Punto | 1 |

**Fin del juego parcial y de la partida.** Un juego parcial (mano) termina cuando se han jugado las 4 jugadas; los jugadores muestran sus cartas para verificar pares/juego. Un juego completo termina cuando una pareja llega o supera 8 amarrakos (40 piedras), o de inmediato si alguien acepta un órdago (se muestran todas las cartas y gana quien tenga mejor jugada en ese momento). La partida completa la gana quien primero gane 3 juegos completos.

*Fuera de alcance deliberado:* el reglamento original también describe una modalidad "con plato" para apuestas de dinero real entre jugadores presenciales. No aplica a una implementación de puntuación online y queda descartada salvo que el equipo indique lo contrario.

---

## 10. Reglas funcionales — Tute (PBI-05, prioridad media)

Basado en las reglas oficiales aportadas por el equipo. A diferencia de Guiñote y Mus, el reglamento del Tute define **tres variantes con mecánica distinta según el número de jugadores** — no es solo "menos gente en la mesa": cambia si existe fase de robo o no. **Decisión de equipo: PBI-05 implementa únicamente el Tute para 4 jugadores por parejas** (reutiliza el mismo patrón de mesa y motor que Guiñote). Las variantes de 2 y 3 jugadores quedan documentadas por completitud pero **fuera de alcance actual**; si se quisieran más adelante, serían una PBI nueva.

**Baraja, orden y valor (común a las 3 variantes).** Española de 40 cartas. De mayor a menor: As, Tres, Rey, **Caballo, Sota**, Siete, Seis, Cinco, Cuatro, Dos.

| Carta | Valor |
|---|---|
| As | 11 |
| Tres | 10 |
| Rey | 4 |
| Caballo | 3 |
| Sota | 2 |
| Resto ("cartas blancas") | 0 |

⚠️ Aquí el **Caballo vale más que la Sota** — al revés que en Guiñote (§8). Ver el aviso de esa sección sobre no compartir esta tabla entre los dos motores sin parametrizarla por juego.

**Roles de mesa.** "Mano" = quien empieza la baza; "postre" = quien la termina y reparte la siguiente mano. La dirección para repartir, colocarse y jugar es siempre antihoraria.

### Tute para 4 jugadores (por parejas) — única variante en el alcance actual

- 2 parejas sentadas una frente a otra. El dador (por sorteo) reparte **10 cartas** a cada jugador, de una en una, y voltea su propia última carta como triunfo (pinta).
- Reglas de juego: obligatorio **asistir, montar, fallar y pisar** (si vas a fallar y ya hay triunfo jugado, hay que superarlo si se puede). Si no se puede pisar, se permite el **contrafallo** (jugar cualquier carta).
- Cantes: tras ganar baza, **los dos miembros de la pareja pueden cantar a la vez**, un acuse cada uno (Rey+Caballo del mismo palo: 40 si es triunfo — "las cuarenta" —, 20 si no — "las veinte en [palo]").
- Tute: reunir los 4 Reyes ("Tute de reyes") o los 4 Caballos ("Tute de caballos") en la mano de **un solo** integrante de la pareja gana la mano al instante.
- Gana la mano la pareja con más tantos (cartas de bazas + cantes + últimas).

### Tute para 2 jugadores (fuera de alcance actual — documentado por completitud)

- Se reparten **8 cartas** cada uno; el resto queda en un mazo (baceta) bajo la carta de triunfo volteada.
- **Mientras queda baceta:** solo es obligatorio asistir al palo de triunfo (sin necesidad de "montarlo"); para el resto de palos no hay obligación de asistir ni fallar. **Al agotarse la baceta:** pasa a ser obligatorio asistir, montar y fallar (arrastre completo).
- Tras cada baza, cada jugador roba una carta (el ganador roba primero y sale en la siguiente).
- La pinta puede cambiarse por el 7 del mismo palo (si es As/Tres/figura) o por el 2 (si es carta blanca); este cambio y los cantes solo pueden hacerse justo después de ganar una baza.
- **Capote:** jugada especial — anunciándolo de antemano, un jugador puede intentar ganar las 8 bazas que quedan tras agotarse la baceta; si el rival gana aunque sea una, es el rival quien gana la mano entera.
- ⚠️ En esta variante **no se admite la jugada de Tute** (4 reyes/caballos): solo se gana por puntos (101) o por Capote.
- Igual que en Guiñote: si nadie llega a 101 en una mano, se reparte una segunda ("dar la vuelta") llevando el tanteo de memoria.

### Tute para 3 jugadores ("Tute Arrastrado") (fuera de alcance actual — documentado por completitud)

- Participan 4 personas en la mesa pero juegan 3 por mano; quien reparte esa mano no juega ni cobra ni paga, y ese turno de repartir rota.
- Se reparten **13 cartas** a cada uno de los 3 jugadores activos (39 cartas) y se voltea la última carta del mazo (la 40ª) como triunfo — **no queda baceta**: arrastre completo desde la primera baza (asistir, montar, fallar y pisar obligatorios; contrafallo permitido si no se puede pisar).
- Solo se puede cantar un acuse por baza ganada, y **es obligatorio cantar "las cuarenta" antes que "las veinte"** si un jugador tiene ambas disponibles.
- Gana quien hace más tantos de los 3; el Tute (reyes o caballos) también es válido aquí.
- *Fuera de alcance:* el reglamento describe además variantes de cobro con dinero real ("con plato" / "sin plato") pensadas para partidas presenciales con apuestas; no aplican a una implementación de puntuación online y quedan descartadas salvo indicación contraria del equipo.

**Tanteo (común a las 3 variantes).** Puntúan las cartas de las bazas ganadas, los acuses (40 si es triunfo, 20 si no) y la última baza del juego ("diez últimas" = 10 puntos, y desempata). Ganar una mano: cantar Tute (donde esté permitido) o alcanzar 101 tantos.

**Fin de partida.** Igual que en Guiñote (§8), el reglamento deja el número de manos a acuerdo previo de los jugadores — **decisión de equipo: también a una sola mano.** Ganar una mano (cantando Tute o llegando a 101) gana la partida.

---

## 11. Flujo end-to-end (para entender cómo encajan todas las piezas)

1. El usuario abre la aplicación (cliente Godot instalado) y hace login → `POST /auth/login` contra el backend.
2. Ve el lobby → `GET /salas`. Crea o se une a una → `POST /salas` o `POST /salas/:id/unirse`.
3. Cuando la sala se completa, el backend le da la dirección (`host:puerto`) del servidor de partida (`GAME_SERVER_ADDRESS`).
4. El cliente conecta por ENet y envía `unirse_partida { usuario_id, token, sala_id }`. El servidor verifica el token y pide la sala al backend (`GET /interno/salas/:id`).
5. El servidor de partida inicia la partida usando el motor genérico (§7) + el módulo del juego correspondiente, y empieza a intercambiar `jugar_carta` / `estado_partida`.
6. Al terminar, el servidor de partida llama a `POST /interno/partidas` para persistir el resultado.
7. El cliente recibe `partida_terminada` y puede volver al lobby o consultar el historial (`GET /usuarios/:id/historial`).

---

## 12. Cómo mantener esto sincronizado

- Si alguien cambia un contrato (un campo de la API, un mensaje de red, una regla), **se actualiza este archivo en el mismo Pull Request** — no después, no "ya lo digo en el chat del grupo".
- Antes de pedirle a vuestra IA que implemente una PBI, decidle explícitamente qué sección de este documento es la relevante (por ejemplo: "implementa el endpoint POST /auth/registro según la sección 5 de analisis_funcional.md").
- Las secciones marcadas con ⚠️ son avisos permanentes para quien programe (p. ej. que Guiñote y Tute no comparten la tabla de valores de cartas), no decisiones pendientes.
- **Corrección de reglas (23/09/2026):** la fuente usada originalmente para §8 (Guiñote) tenía mal el reparto y la fase de robo; se ha corregido contra el reglamento oficial del torneo aportado por el equipo. Mus (§9) y Tute (§10) no se han tocado en esta revisión — si alguien detecta el mismo tipo de problema en esas secciones, hay que avisar para corregirlas también con una fuente igual de fiable.
- **Estado actual:** las reglas de Mus y Tute siguen cerradas tal como estaban, con sus decisiones de producto ya tomadas (Tute limitado a la variante de 4 jugadores por parejas, sin señas en Mus online). Las de Guiñote (§8) están corregidas y cerradas salvo el punto pendiente señalado arriba; el resto de §8 ya se puede implementar directamente.
