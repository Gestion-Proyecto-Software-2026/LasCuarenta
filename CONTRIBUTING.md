# Cómo contribuir

Flujo de trabajo del equipo: ramas, Pull Requests y cuándo se considera una PBI terminada. Para el **qué** (contratos de API, protocolo de red, reglas de cada juego) ver [`docs/analisis_funcional_app.md`](./docs/analisis_funcional_app.md); para el **cómo se despliega** ver [`docs/arquitectura.md`](./docs/arquitectura.md).

---

## 1. `main` es la única rama larga viva

- Protegida: ningún commit directo. Todo entra por Pull Request.
- Un PR necesita al menos **1 revisión aprobada** de otra persona del equipo y los checks de CI (`Backend CI`, `Godot CI`) en verde antes de fusionar.
- `main` debe quedar siempre en estado desplegable — nada a medias se fusiona aquí.
- Las versiones del cliente no usan rama propia: salen de un tag (`v0.1.0`, `v0.2.0`...) sobre `main`, que es lo que dispara `godot-release.yml`.

## 2. Una rama por PBI o tarea — nunca por persona

Nombre de la rama atado al Issue de la PBI, para que se pueda seguir de un vistazo qué resuelve:

```
pbi-01-registro-autenticacion
pbi-02-lobby-salas
pbi-06-historial
```

Se crea desde `main` actualizado y se borra al fusionar su PR.

## 3. PBIs grandes (talla L/XL) se rompen en subtareas, no en una rama única

PBI-03 (Guiñote) y PBI-04 (Mus) son XL. Mantenerlas en una sola rama hasta estar "completas" acumula semanas de deriva respecto a `main` y produce un PR imposible de revisar. En vez de eso, cada subtarea del Issue tiene su propia rama y su propio PR directo a `main`:

```
pbi-03-reparto-y-robo
pbi-03-fase-arrastre
pbi-03-cantes
pbi-03-tanteo-y-fin-partida
```

Esto encaja con que `MotorDeJuego` es una interfaz (`docs/analisis_funcional_app.md` §7): se puede fusionar parte del motor de un juego sin romper nada, porque `RoomManager` no lo invoca en producción hasta que el PBI completo esté cerrado.

Si dos personas comparten una PBI grande, mejor repartir en subtareas independientes (cada una con su rama/PR) que dos personas empujando a la misma rama.

## 4. Lista completa de ramas por PBI

Aplicando las reglas de arriba a las 9 PBI de la pila (talla y prioridad según la Práctica 1 entregada):

**Prioridad alta**

| PBI | Talla | Rama(s) |
|---|---|---|
| PBI-01 — Registro y autenticación | M | `pbi-01-registro-autenticacion` |
| PBI-02 — Lobby y gestión de salas | L | `pbi-02-listar-y-crear-sala`, `pbi-02-unirse-a-sala` |
| PBI-03 — Partida completa de Guiñote | XL | `pbi-03-reparto-y-robo`, `pbi-03-fase-arrastre`, `pbi-03-cantes`, `pbi-03-tanteo-y-fin-partida` |

**Prioridad media**

| PBI | Talla | Rama(s) |
|---|---|---|
| PBI-04 — Partida completa de Mus | XL | `pbi-04-reparto-y-fase-mus`, `pbi-04-jugadas-y-apuestas`, `pbi-04-cobro-y-fin-partida` |
| PBI-05 — Partida completa de Tute | L | `pbi-05-reparto-y-arrastre`, `pbi-05-cantes-y-tute`, `pbi-05-tanteo-y-fin-partida` |
| PBI-06 — Historial y estadísticas | M | `pbi-06-historial-estadisticas` |

**Prioridad baja**

| PBI | Talla | Rama(s) |
|---|---|---|
| PBI-07 — Ranking de jugadores | S | `pbi-07-ranking-jugadores` |
| PBI-08 — Chat en partida | S | `pbi-08-chat-partida` |
| PBI-09 — Moderación de salas | S | `pbi-09-moderacion-salas` |

Las M/S van en una sola rama porque no compensa trocearlas. PBI-02 se separa en "listar+crear" vs "unirse" porque son los dos únicos bloques con lógica distinta (expulsar ya es PBI-09 aparte). PBI-03 sigue las fases reales del reglamento de Guiñote (§8: robo, arrastre, cantes, tanteo/fin). PBI-04 sigue las fases del Mus (§9: reparto+decisión de mus, jugadas con sus apuestas, cobro final). PBI-05 reutiliza el patrón de Guiñote pero sin fase de robo, por eso le bastan 3 subtareas en vez de 4.

Estas ramas se actualizan si el desglose real de un PBI cambia durante el grooming — no son un compromiso rígido, son el punto de partida.

## 5. Convención de tests

**Backend (Jest + Supertest) — ya se puede seguir:**
- Un fichero de test por recurso en `backend/tests/`, reflejando `backend/src/routes/`: `auth.test.js`, `lobby.test.js`, `historial.test.js`, `ranking.test.js` — mismo patrón que ya usa `health.test.js` (Supertest contra `app` directamente, sin levantar un servidor real).
- Las rutas que tocan PostgreSQL necesitan una base de datos de test. Recomendado: la misma `db` de `docker-compose.yml`, pero con una base separada (`cartas_online_test`) para no mezclar datos con desarrollo — no compartáis la `cartas_online` de trabajo diario.
- La Definición de Hecho exige que estos tests **pasen** en CI; el 60% de cobertura mínima aplica solo a la lógica de juego, no al backend.

**Juego (GUT):**
- GUT barre `game/tests/` y sus subcarpetas (configurado en `game/.gutconfig.json`). Solo se ejecutan los ficheros `test_*.gd` que extienden `GutTest`.
- Tests unitarios de `shared/` y `server/game_engine/` en `game/tests/unit/`, reflejando la ruta del script probado (p. ej. `shared/baraja.gd` → `tests/unit/shared/test_baraja.gd`, `server/game_engine/guinote/motor_guinote.gd` → `tests/unit/server/game_engine/guinote/test_motor_guinote.gd`). Los que necesitan varias piezas a la vez (`RoomManager` + un motor) van en `game/tests/integration/`.
- El 60% de cobertura mínima aplica a la lógica de juego (`shared/` + `server/game_engine/`), no al cliente.
- En local, igual que en CI (Godot 4.7.2): `godot --headless --path game -s addons/gut/gut_cmdln.gd`.
- Nombres de ficheros y carpetas de `game/` en `snake_case`, igual que el `class_name` en `snake_case` (`class_name Baraja` → `baraja.gd`), según la guía de estilo de Godot. Cada escena del cliente va en su propia carpeta junto a su script (`client/scenes/carta/carta.tscn` + `carta.gd`).

## 6. Antes de abrir un PR

Checklist resumido de la Definición de Hecho (fuente completa: informe de la Práctica 1 entregado, §4):

- [ ] Tests automáticos (unitarios y de integración) pasan en CI.
- [ ] Cobertura de tests de la lógica de juego ≥ 60%.
- [ ] Documentación (`README`/`docs/`) actualizada si la PBI la afecta.
- [ ] Backend formateado con Prettier.
- [ ] GDScript sigue la [guía de estilo oficial de Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).
- [ ] Funcionalidad probada en el entorno de pruebas.

## 7. Estructura de carpetas (recordatorio)

| Carpeta | Contenido |
|---|---|
| `backend/` | API REST (Node.js + Express + PostgreSQL) |
| `game/client/` | Cliente Godot — solo presentación e input |
| `game/server/` | Servidor de partida — lógica autoritativa |
| `game/shared/` | Lo que cliente y servidor de partida necesitan sin duplicar |
| `game/tests/` | Tests GUT de la lógica de juego |
| `game/addons/gut/` | Framework de testing GUT |
| `infra/` | Configuración de despliegue (nginx + TLS) |
| `docs/` | Documentación técnica y de arquitectura |

Detalle completo de responsabilidades por carpeta en `docs/arquitectura.md` §2.
