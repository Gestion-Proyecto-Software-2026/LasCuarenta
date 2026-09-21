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

`servidor_direccion` es la IP/host y puerto (`host:puerto`) a la que el cliente debe conectarse por ENet una vez la sala está completa.

### Historial y ranking (PBI-06, PBI-07)
| Método | Ruta | Respuesta |
|---|---|---|
| GET | `/usuarios/:id/historial` | `200 [{ partida_id, juego, fecha, resultado, gano }]` |
| GET | `/ranking?juego=guinote` | `200 [{ usuario_id, nombre_visible, puntos_totales, posicion }]` |

### Interno (solo lo llama el servidor de partida, con secreto compartido servidor-a-servidor, nunca el cliente)
| Método | Ruta | Body |
|---|---|---|
| POST | `/interno/partidas` | `{ sala_id, resultado: { equipos: [...], puntos: [...] } }` |

---

## 6. Protocolo en tiempo real (cliente ↔ servidor de partida)

Mensajes sobre ENet (UDP), mapeados a RPCs de Godot. Formato sugerido: `{ tipo, payload }`.

**Cliente → Servidor**

| Mensaje | Payload | Cuándo |
|---|---|---|
| `unirse_partida` | `{ usuario_id, token }` | Al conectar por ENet |
| `jugar_carta` | `{ carta_id }` | Turno del jugador |
| `cantar` | `{ palo }` | Guiñote/Tute, tras ganar baza |
| `mus` / `no_mus` | — | Fase de decisión en Mus |
| `apostar` | `{ tipo, cantidad }` | Envite/órdago en Mus |
| `chat_enviar` | `{ mensaje }` | PBI-08, en cualquier momento de la partida |

**Servidor → Cliente**

| Mensaje | Payload | Cuándo |
|---|---|---|
| `partida_iniciada` | `{ config }` | Al completarse la sala |
| `estado_partida` | snapshot filtrado (ver §7) | Tras cada acción válida |
| `partida_terminada` | `{ resultado }` | Al finalizar |
| `chat_mensaje` | `{ usuario_id, mensaje }` | PBI-08, al recibir un `chat_enviar` válido de cualquier jugador de la sala |
| `error` | `{ mensaje }` | Jugada inválida, turno equivocado, etc. |

**Regla importante:** el servidor nunca envía a un cliente las cartas en mano de otro jugador. El snapshot se filtra por destinatario antes de enviarse (ver `vista_para_jugador` en §7).

---

## 7. Interfaz común del motor de reglas

Contrato que debe implementar cada módulo de juego (`guinote/`, `mus/`, `tute/`) dentro de `game/server/game_engine/`. Es el punto más importante de todo el documento: si esto queda mal diseñado pensando solo en Guiñote, Mus y Tute cuestan mucho más de lo necesario.

```gdscript
# Contrato que debe cumplir cada módulo de juego
class_name MotorDeJuego

func iniciar(jugadores: Array) -> EstadoPartida:
    pass  # reparte cartas, decide quién empieza, etc.

func jugadas_validas(estado: EstadoPartida, jugador_id: int) -> Array:
    pass  # qué puede hacer este jugador ahora mismo

func aplicar_jugada(estado: EstadoPartida, jugador_id: int, jugada: Dictionary) -> EstadoPartida:
    pass  # valida y aplica; si no es válida, error, no excepción silenciosa

func ha_terminado(estado: EstadoPartida) -> bool:
    pass

func calcular_resultado(estado: EstadoPartida) -> Dictionary:
    pass  # puntos finales por equipo/jugador

func vista_para_jugador(estado: EstadoPartida, jugador_id: int) -> Dictionary:
    pass  # oculta las cartas de los demás antes de enviar al cliente
```

`RoomManager` (en `game/server/room_manager.gd`) no conoce las reglas de ningún juego concreto — solo sabe hablar contra esta interfaz. Añadir un juego nuevo no debería tocar ni una línea de `room_manager.gd`.

---

## 8. Reglas funcionales — Guiñote (PBI-03, prioridad alta)

Basado en las reglas oficiales aportadas por el equipo. Sección cerrada por completo.

**Jugadores y disposición.** 4 jugadores en 2 parejas, sentados alternos (0-2 vs 1-3), enfrentados entre sí. *(El propio reglamento contempla también una variante individual a 2-3 jugadores, pero el criterio de aceptación de PBI-03 pide explícitamente "por parejas", así que esa variante individual queda fuera de esta PBI — sería una PBI nueva si se quisiera más adelante.)*

**Baraja, orden y valor de las cartas.** Española de 40 cartas. De mayor a menor: **As, Tres, Rey, Sota, Caballo**, Siete, Seis, Cinco, Cuatro, Dos.

| Carta | Valor |
|---|---|
| As | 11 |
| Tres | 10 |
| Rey | 4 |
| Sota | 3 |
| Caballo | 2 |
| Resto (7, 6, 5, 4, 2) | 0 |

⚠️ **Aviso al implementar:** en Guiñote la **Sota vale más que el Caballo** (en orden y en puntos) — al revés que en el Tute (§10), donde el Caballo vale más que la Sota. Si el motor de reglas comparte alguna tabla de valores entre los dos juegos, hay que parametrizarla por juego para no arrastrar este error.

**Reparto.** Se sortea quién reparte. El dador baraja, da a cortar al jugador de su izquierda, y reparte **todas las cartas** (10 por jugador, de una en una), volteando la última como **pinta** (marca el palo de triunfo). No hay fase de robo/mazo: las 10 cartas de cada jugador se juegan directamente desde la primera baza — el juego es "de arrastre" desde el principio, no solo al final. El turno de repartir rota por partidas completas (no por manos), en sentido antihorario.

**Turno y juego de bazas.** Empieza el jugador siguiente al que reparte ("mano"). En cada baza, los demás jugadores deben, en este orden de obligación: **asistir** (seguir el palo de salida) si pueden, **montar** (superar la carta ganadora del palo de salida) si pueden, o **fallar** (jugar triunfo) si no tienen el palo de salida. Gana la baza el triunfo más alto jugado; si no se jugó ningún triunfo, gana la carta más alta del palo de salida. Quien gana la baza se la lleva boca abajo y sale en la siguiente.

**Acuses (cantes).** La pareja que gana una baza puede cantar Sota+Rey del mismo palo que tenga en mano (máximo un acuse por miembro de la pareja, y solo justo después de ganar baza; para cantar un segundo acuse hay que esperar a ganar otra baza). Vale **40 puntos** si es del palo de triunfo ("las cuarenta"), o **20 puntos** si es de otro palo ("las veinte en [palo]").

**Fin de mano y tanteo.** Se juega hasta que todos agotan sus 10 cartas. Puntúan: el valor de las cartas de las bazas ganadas + los acuses cantados + **10 puntos** extra para quien gane la última baza ("las diez de últimas", que además sirve de desempate).

**Formas de ganar una mano:**
1. **Cantar Tute** — reunir en la mano **las 4 sotas** ("Tute de sotas") o **los 4 reyes** ("Tute de reyes"): gana la mano al instante, sin importar el tanteo. *(En Guiñote el Tute es de sotas o reyes; en el juego de Tute, §10, es de caballos o reyes — no reutilizar la misma constante entre los dos motores de reglas.)*
2. **Alcanzar 101 tantos.** Si ambas parejas superan 101 en la misma mano, gana la de mayor diferencia; si empatan a tantos, gana quien hizo la última baza.
3. Si nadie canta Tute ni llega a 101, se reparte una segunda mano ("dar la vuelta"), repartida por quien ganó las diez de últimas de la mano anterior. En esta segunda mano hay que llevar de memoria (sin volver a mirar las bazas ya ganadas) el acumulado de ambas manos; en cuanto un jugador cree haber llegado a 101 lo canta y el juego se detiene para comprobar. Si al comprobar no llegaba, gana automáticamente la pareja contraria.

**Fin de partida.** El reglamento oficial deja el número de manos "determinado inicialmente" por acuerdo de los jugadores, sin fijar una cifra — **decisión de equipo: la partida se juega a una sola mano.** En cuanto una pareja gana una mano (cantando Tute o llegando a 101), gana la partida completa; no hay marcador entre manos que implementar.

**Penalizaciones (renuncio).** Cantar 101 sin haberlos alcanzado realmente hace perder la mano automáticamente. Lo mismo ocurre si un jugador comete "renuncio": no asistir, montar o fallar pudiendo hacerlo, en ese orden de obligación.

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
3. Cuando la sala se completa, el backend le da la dirección (`host:puerto`) del servidor de partida.
4. El cliente conecta por ENet y envía `unirse_partida`.
5. El servidor de partida inicia la partida usando el motor genérico (§7) + el módulo del juego correspondiente, y empieza a intercambiar `jugar_carta` / `estado_partida`.
6. Al terminar, el servidor de partida llama a `POST /interno/partidas` para persistir el resultado.
7. El cliente recibe `partida_terminada` y puede volver al lobby o consultar el historial (`GET /usuarios/:id/historial`).

---

## 12. Cómo mantener esto sincronizado

- Si alguien cambia un contrato (un campo de la API, un mensaje de red, una regla), **se actualiza este archivo en el mismo Pull Request** — no después, no "ya lo digo en el chat del grupo".
- Antes de pedirle a vuestra IA que implemente una PBI, decidle explícitamente qué sección de este documento es la relevante (por ejemplo: "implementa el endpoint POST /auth/registro según la sección 5 de analisis_funcional.md").
- Las secciones marcadas con ⚠️ son avisos permanentes para quien programe (p. ej. que Guiñote y Tute no comparten la tabla de valores de cartas), no decisiones pendientes — ya no queda ninguna decisión de equipo abierta en §8-10.
- **Estado actual (tras incorporar las reglas oficiales de los 3 juegos):** las reglas de Guiñote, Mus y Tute están cerradas, incluyendo las tres decisiones de producto que las reglas por sí solas no podían fijar: partidas a una sola mano (Guiñote y Tute), Tute limitado a la variante de 4 jugadores por parejas, y sin señas en Mus online. Cualquiera de los 4 puede empezar a implementar directamente contra §8-10 sin esperar más aclaraciones.
