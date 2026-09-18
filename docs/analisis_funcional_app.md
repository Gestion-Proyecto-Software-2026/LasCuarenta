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
| Estilo de código backend | `camelCase`, ESLint + Prettier | — | Convención estándar de JS/Node |
| Flujo de ramas | rama por PBI/tarea + PR revisada por otra persona antes de `main` | commits directos a `main` | Ya forma parte de la Definición de Hecho |

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

**Servidor → Cliente**

| Mensaje | Payload | Cuándo |
|---|---|---|
| `partida_iniciada` | `{ config }` | Al completarse la sala |
| `estado_partida` | snapshot filtrado (ver §7) | Tras cada acción válida |
| `partida_terminada` | `{ resultado }` | Al finalizar |
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

- **Jugadores:** 4, en 2 parejas fijas (asientos alternos: 0-2 vs 1-3).
- **Baraja:** española de 40 cartas (1, 2, 3, 4, 5, 6, 7, 10, 11, 12 en cada palo).
- **Valor por carta:** As=11, 3=10, Rey=4, Caballo=3, Sota=2; resto=0.
- **Reparto:** 6 cartas por jugador; el resto queda en el mazo boca abajo, con la carta inferior volteada marcando el **palo de triunfo**.
- **Turno:** sentido horario. Mientras queda mazo, cada jugador roba una carta después de jugar.
- **Ganar una baza:** gana la carta de más valor del palo de salida, salvo que se juegue triunfo, en cuyo caso gana el triunfo más alto. Quien gana se lleva las cartas y sale en la siguiente baza.
- **Cantar:** si un jugador tiene Rey+Caballo del mismo palo en mano, puede cantarlos justo después de ganar una baza y antes de jugar la siguiente carta: **20 puntos** (palo normal) o **40 puntos** (palo de triunfo).
- **Fase de arrastre:** al agotarse el mazo, cambia la regla — pasa a ser obligatorio asistir al palo de salida si se tiene, y superar la carta ganadora si es posible.
- **Fin de mano:** al jugarse todas las cartas. La pareja que gana la última baza suma **10 puntos extra** ("las diez de últimas").
- **Puntuación y victoria:** puntos de las bazas ganadas + cantes + últimas. ⚠️ *El umbral exacto para ganar la partida (habitualmente 101 puntos) y qué pasa si nadie llega ("vueltas") varía según la variante — fijadlo como equipo y actualizad esta sección con la decisión final antes de implementar el cómputo de puntuación.*

---

## 9. Reglas funcionales — Mus (PBI-04, prioridad media)

Resumen funcional de alto nivel — el Mus tiene bastantes variantes regionales en los detalles de apuestas, así que antes de implementarlo hay que cerrar una versión concreta como equipo.

- **Jugadores:** 2 o 4 (por parejas si son 4).
- **Baraja:** española de 40 cartas. Particularidad del Mus: a efectos de comparar manos, **Rey y 3 valen igual** (las cartas "altas"), y **As y 2 valen igual** (las cartas "bajas").
- **Fases de cada mano, en orden:** *Mus* (los jugadores pueden pedir repetir reparto si todos están de acuerdo) → *Grande* (gana quien tiene las cartas más altas) → *Chica* (gana quien tiene las más bajas) → *Pares* (tener parejas/tríos/dobles parejas) → *Juego* o *Punto* (sumar el valor de las 4 cartas; 31+ es "Juego", si nadie llega se compara "Punto").
- **Apuestas:** en cada fase los jugadores pueden hacer *envite* (subir apuesta) u *órdago* (apostar la partida entera); el rival puede igualar, subir o retirarse.
- **Señas:** en el Mus presencial las parejas se comunican gestos permitidos entre compañeros. Para la versión online, **es una decisión de producto pendiente** si se implementa algún mecanismo equivalente o se prescinde de él — anotadlo aquí cuando se decida.
- ⚠️ *Puntuación exacta por fase y condición de victoria: pendiente de fijar como equipo antes de implementar.*

---

## 10. Reglas funcionales — Tute (PBI-05, prioridad media)

- **Jugadores:** 2 a 4 (variante clásica individual; valorad si queréis además una variante por parejas como en Guiñote).
- **Baraja y valor de cartas:** igual que Guiñote (As=11, 3=10, Rey=4, Caballo=3, Sota=2, resto=0).
- **Cantes:** igual mecánica que Guiñote (Rey+Caballo del mismo palo = 20, o 40 si es triunfo).
- **Tute:** reunir en mano las 4 cartas de un mismo valor (p. ej., los 4 Reyes) permite cantar "Tute", con una bonificación de puntos grande o victoria directa de la mano, según la variante que elijáis.
- **Resto de mecánica** (turnos, arrastre, última baza): análoga a Guiñote.
- ⚠️ *Qué variante de Tute exacta (con o sin parejas, qué combinaciones de "Tute" son válidas) queda pendiente de decidir como equipo.*

---

## 11. Flujo end-to-end (para entender cómo encajan todas las piezas)

1. El usuario abre la web (cliente Godot exportado) y hace login → `POST /auth/login` contra el backend.
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
- Las secciones marcadas con ⚠️ son las que aún no están cerradas — resolvedlas en equipo antes de que alguien empiece a programar esa parte, para no tener que rehacer trabajo.
