# Arquitectura

**Estado:** borrador vivo — actualizadlo en el mismo PR que cambie un componente o un límite de confianza (ver §7).

Este documento describe **cómo se despliegan y comunican las piezas** del sistema. Para los contratos exactos (modelo de datos, endpoints REST, mensajes ENet, reglas de cada juego) la fuente de verdad es [`analisis_funcional_app.md`](./analisis_funcional_app.md) — no se duplican aquí para no mantener dos versiones del mismo contrato.

---

## 1. Visión general

Tres piezas con responsabilidades separadas: un cliente que solo pinta, un backend transaccional, y un servidor de partida que es la única autoridad sobre el estado de una partida en curso.

- **Cliente** — proyecto Godot (GDScript) exportado a ejecutable nativo (Windows/Linux). Solo presentación e input; nunca decide si una jugada es válida.
- **Backend REST** (Node.js + Express + PostgreSQL) — todo lo transaccional: cuentas, lobby/salas, historial, ranking. Sin conocimiento de las reglas de los juegos.
- **Servidor de partida** (Godot headless, GDScript) — autoridad única sobre el estado de una partida. Aloja el motor de reglas (`MotorDeJuego`, ver `analisis_funcional_app.md` §7) y no persiste nada por sí mismo: notifica el resultado final al backend.

```
                         ┌────────────────────────────┐
                         │       Cliente Godot        │
                         │  (Windows / Linux, nativo) │
                         └───────────┬─────────┬──────┘
                                     │         │
                      HTTPS (TLS) ───┘         └─── ENet/UDP (sin TLS)
                                     │         │
                         ┌───────────▼───┐   ┌─▼───────────────────────┐
                         │  nginx (proxy │   │ Servidor de partida     │
                         │  inverso, TLS)│   │ (Godot headless)        │
                         └───────────┬───┘   │  RoomManager            │
                                     │       │  └─ MotorDeJuego        │
                         ┌───────────▼───┐   │     (guinote/mus/tute)  │
                         │ Backend       │   └───────────┬─────────────┘
                         │ Node+Express  │               │
                         └───────────┬───┘  HTTP interno │ (secreto compartido)
                                     │  ◀───────────────┘
                              SQL    │  POST /interno/partidas
                         ┌───────────▼───┐
                         │  PostgreSQL   │
                         └───────────────┘
```

Diagrama de componentes exportado: `diagramas/arquitectura.png` (pendiente de añadir; el diagrama ASCII de arriba es la referencia mientras tanto).

**Estado actual frente al diagrama.** Cliente y servidor de partida son el mismo proyecto (`game/`), y el servidor es la escena `escenas/partida.tscn` arrancada en modo servidor: aloja **una** partida por proceso, conecta a los jugadores por IP directa y no habla con el backend. Lo que sí se cumple ya es el principio central: el servidor es la única autoridad y la mesa solo pinta la vista que recibe. El `RoomManager` del diagrama (salas, JWT, backend) existía en el `game/` anterior a la unificación y queda pendiente de reintegrar (ver `README.md` §1).

---

## 2. Componentes y responsabilidades por carpeta

Correspondencia directa entre el árbol del repositorio y las tres piezas de §1 (recordatorio; el detalle vive en `analisis_funcional_app.md` §3):

| Carpeta | Pieza | Responsabilidad | Regla dura |
|---|---|---|---|
| `game/escenas/` | Cliente + Servidor de partida | Menú de modos y escena de partida, que arranca como servidor o como jugador | — |
| `game/compartido/Escenas/` | Cliente | Presentación e input: carta y tapete (la mesa) | Nunca decide si una jugada es válida — pinta la vista y las jugadas válidas que le manda el servidor |
| `game/compartido/logica/game_master/` | Servidor de partida | Controladores de red: reciben jugadas, se las pasan al motor y difunden el estado | Solo actúan en el servidor (`multiplayer.is_server()`) |
| `game/compartido/logica/motores/` | Servidor de partida | Reglas de cada juego (`MotorDeJuego` + `guinote/`, `tute/`, `tute_dos/`, `mus/`) y `cartas.gd` | Lógica pura: ningún script hereda de un nodo ni conoce la red |
| `backend/` | Backend REST | Cuentas, lobby, historial, ranking | Sin conocimiento de las reglas de ningún juego |
| `infra/` | Despliegue | nginx + TLS delante del backend | El servidor de partida (ENet/UDP) no pasa por aquí |
| `docs/` | — | Documentación técnica y de arquitectura | — |

Dentro de `backend/src/`, la estructura actual ya separa por capa: `routes/` (un fichero por recurso: `auth.js`, `lobby.js`, `historial.js`, `ranking.js`), `middleware/` (`auth.js` = verificación de JWT), `models/` (`db.js` = pool de conexión `pg`, único punto de acceso a PostgreSQL). `app.js` monta cada grupo de rutas bajo su prefijo (`/api/auth`, `/api/salas`, `/api/usuarios`, `/api/ranking`) y expone `/health`; `index.js` solo arranca el servidor HTTP.

En `game/`:
- `escenas/menu.*` — elige uno de los 6 modos (`compartido/logica/modos.gd`: juego, jugadores y puerto). Con `-- modo=<id>` se lo salta.
- `escenas/partida.*` — crea la mesa y el controlador del modo, abre el `ENetMultiplayerPeer` (servidor o cliente, puerto 8911–8916 según el modo) y sienta a los jugadores por orden de conexión. Si alguien se va a mitad de partida, la cancela y avisa a los demás.
- `compartido/logica/game_master/juego_motor.gd` — controlador genérico (`Juego_Motor`): recibe jugadas por RPC, las aplica con el motor y manda a cada jugador su vista (`vista_para_jugador`) y sus jugadas válidas. No conoce ninguna regla de juego. Lleva los 6 modos: Guiñote, Tute y Mus, a 2 y a 4.
- `compartido/logica/game_master/reglas_tute.gd` — reglas puras del Tute por parejas (`ReglasTute`), que usa `motores/tute/motor_tute.gd`.
- `compartido/logica/motores/motor_de_juego.gd` — clase base abstracta `MotorDeJuego` (con `estado_partida.gd` y `resultado_jugada.gd`), copiada del `game/server/game_engine/` anterior; contrato completo en `analisis_funcional_app.md` §7. Las cartas son ids de texto (`cartas.gd`).

**Pendiente de reintegrar** (estaba en el `game/` anterior a la unificación, sigue en el historial de `main`, commit `a6a6bdc`): `main_server.*`, `room_manager.gd`, `sala_activa.gd`, `verificador_jwt.gd`, `cliente_backend.gd`, el autoload `CanalRed` y las pantallas de login, registro, recuperar y lobby.

---

## 3. Tecnologías por componente

| Componente | Tecnología | Notas |
|---|---|---|
| Cliente | Godot 4.7, GDScript | Exportado a ejecutable Windows/Linux, no a Web |
| Red cliente ↔ servidor de partida | `ENetMultiplayerPeer` sobre UDP | Sin TLS en este canal (ver §5) |
| Servidor de partida | Godot 4.7 (con o sin pantalla), GDScript | `godot --headless --path game res://escenas/partida.tscn -- modo=<id> servidor`, puerto del modo (`puerto=N` para cambiarlo). Hoy no lee variables de entorno; al reintegrar las salas volverá a necesitar `JWT_SECRET`, `INTERNAL_API_SECRET` y `BACKEND_URL` |
| Backend | Node.js + Express | `backend/src/app.js` |
| Base de datos | PostgreSQL 16 | Extensión `pgcrypto` para `gen_random_uuid()` (`migrations/001_init.sql`) |
| Autenticación | JWT (`jsonwebtoken`) + `bcrypt` para contraseñas | Verificado en `backend/src/middleware/auth.js` |
| Envío de correo | `nodemailer` (SMTP) | Solo para `POST /auth/recuperar`; credenciales en `SMTP_*` (`backend/.env.example`) |
| Proxy inverso / TLS | nginx + Let's Encrypt (Certbot) | Solo delante del backend REST (`infra/nginx/nginx.conf`) |
| Orquestación local/dev | Docker Compose | Levanta `db` + `backend` (`docker-compose.yml`); el cliente y el servidor de partida se ejecutan fuera de Compose (Godot no está dockerizado en este repo) |

---

## 4. Entornos y despliegue

**Desarrollo local:**
1. `docker compose up -d` — levanta `db` (Postgres, puerto expuesto `5432`) y `backend` (puerto `3000`), con `JWT_SECRET` y `DATABASE_URL` de ejemplo en el propio `docker-compose.yml`.
2. Las migraciones de `backend/migrations/` se aplican solas la primera vez, cuando PostgreSQL crea la base de datos (están montadas en `docker-entrypoint-initdb.d`). Con un volumen que ya existe no se vuelven a ejecutar: una migración nueva se aplica a mano, o se empieza de cero con `docker compose down -v` (borra los datos).
3. El juego (servidor de partida y jugadores) se lanza aparte con el editor o la CLI de Godot — no está en `docker-compose.yml` — y hoy no necesita el backend: ver `README.md` §5.2.
4. Para arrancar el backend fuera de Docker (`npm run dev` en `backend/`), copiad `backend/.env.example` a `backend/.env`: `src/index.js` lo carga al arrancar, y las variables que ya existan en el entorno tienen prioridad.

**Producción (según `infra/nginx/nginx.conf`):**
- nginx expone `api.tudominio.com` en el puerto 443, con certificado TLS de Let's Encrypt, y hace `proxy_pass` a `backend:3000`. El puerto 80 solo redirige a HTTPS.
- El servidor de partida no está detrás de nginx: el cliente se conecta directamente por ENet/UDP a la `servidor_direccion` (`host:puerto`) que el backend le entrega al completarse una sala (contrato en `analisis_funcional_app.md` §5).
- No hay todavía definición de cómo se orquesta el servidor de partida en producción (una instancia por sala, un pool, reinicio ante caída, etc.) ni de balanceo entre varias instancias del backend — pendiente de decidir cuando el equipo aborde el despliegue real.

---

## 5. Límites de confianza y seguridad

- **Cliente ↔ Backend (REST):** cifrado (HTTPS vía nginx), porque viajan credenciales de login. Autenticación por JWT en `Authorization: Bearer <token>` en todas las rutas salvo registro, login, recuperación de contraseña y ranking (ver `analisis_funcional_app.md` §5). Las rutas de lobby (listado, creación y unión a salas) también exigen token.
- **Cliente ↔ Servidor de partida (ENet/UDP):** sin TLS — decisión de equipo, ya que es un juego por turnos y no hay credenciales viajando por ese canal (la identidad se validará en `unirse_partida` con el token obtenido del login). ⚠️ **Hoy no se valida ninguna identidad:** cualquiera que conecte al puerto de un modo ocupa el siguiente asiento libre. El servidor sí sigue siendo la única autoridad: las jugadas se validan contra el motor y la mesa nunca decide.
- **Servidor de partida → Backend (HTTP interno):** rutas `GET /interno/salas/:id` (el servidor pide la composición de una sala la primera vez que alguien se une) y `POST /interno/partidas` (resultado final). La comunicación siempre va en ese sentido; el backend nunca llama al servidor de partida. Protegidas por un secreto compartido servidor-a-servidor (no JWT de usuario) mandado en la cabecera `X-Internal-Secret`. Solo las invoca el servidor de partida, nunca el cliente. El secreto vive en la variable de entorno `INTERNAL_API_SECRET` (ya definida en `backend/.env.example` y `docker-compose.yml`); el servidor de partida debe leer el mismo valor de su propia configuración cuando se implemente esa llamada.
- **Tokens de usuario en el servidor de partida:** el servidor de partida verifica el JWT de `unirse_partida` por su cuenta, con el mismo `JWT_SECRET` que el backend. Por tanto `JWT_SECRET` es un secreto compartido entre los dos procesos, igual que `INTERNAL_API_SECRET`; si se filtra desde cualquiera de ellos hay que rotarlo en ambos.
- **Contraseñas:** cifradas con `bcrypt` antes de guardarse (`usuarios.password_hash`).
- El backend no confía en ningún dato de estado de partida que no venga de esa ruta interna — el backend no valida reglas de juego, solo persiste lo que le informa el servidor de partida.

---

## 6. Escalado y requisitos no funcionales relevantes para la arquitectura

Recordatorio de los NFR que condicionan decisiones de arquitectura (fuente completa: informe de la Práctica 1, §4 Definición de Hecho):

- Tiempo de respuesta de las acciones de juego: < 500 ms → motiva UDP/ENet en vez de HTTP para el canal de partida.
- Mínimo de partidas simultáneas sin degradación: 5 → previsto: todas en el mismo proceso headless vía `RoomManager`. Hoy cada partida es un proceso con su puerto (uno por modo), así que solo cabe una partida por modo a la vez; no hay todavía criterio de cuándo pasar a múltiples procesos/instancias.
- Compatibilidad: Windows 10/11 y una distribución Linux común → condiciona que el cliente se exporte como ejecutable nativo por plataforma, no como un único binario multiplataforma.

---

## 7. Cómo mantener esto sincronizado

- Si cambia un componente, un puerto, una tecnología o un límite de confianza, se actualiza este archivo en el mismo Pull Request.
- Los contratos detallados (API, protocolo de red, modelo de datos, reglas de juego) se mantienen únicamente en `analisis_funcional_app.md` — este documento solo referencia las secciones relevantes, no las repite.
- Pendiente: diagrama exportado en `diagramas/arquitectura.png`, y decisión de despliegue/orquestación del servidor de partida en producción (§4).
