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

---

## 2. Componentes y responsabilidades por carpeta

Correspondencia directa entre el árbol del repositorio y las tres piezas de §1 (recordatorio; el detalle vive en `analisis_funcional_app.md` §3):

| Carpeta | Pieza | Responsabilidad | Regla dura |
|---|---|---|---|
| `game/client/` | Cliente | Presentación e input | Nunca decide si una jugada es válida — se lo pregunta al servidor |
| `game/server/` | Servidor de partida | Lógica autoritativa (`RoomManager` + `MotorDeJuego` por juego) | Ningún script hereda de un nodo visual (`Node2D`, `Control`, etc.) |
| `game/shared/` | Cliente + Servidor de partida | Definición de carta, constantes de mensajes de red, tipos comunes | Sin duplicar entre cliente y servidor |
| `backend/` | Backend REST | Cuentas, lobby, historial, ranking | Sin conocimiento de las reglas de ningún juego |
| `infra/` | Despliegue | nginx + TLS delante del backend | El servidor de partida (ENet/UDP) no pasa por aquí |
| `docs/` | — | Documentación técnica y de arquitectura | — |

Dentro de `backend/src/`, la estructura actual ya separa por capa: `routes/` (un fichero por recurso: `auth.js`, `lobby.js`, `historial.js`, `ranking.js`), `middleware/` (`auth.js` = verificación de JWT), `models/` (`db.js` = pool de conexión `pg`, único punto de acceso a PostgreSQL). `app.js` monta cada grupo de rutas bajo su prefijo (`/api/auth`, `/api/salas`, `/api/usuarios`, `/api/ranking`) y expone `/health`; `index.js` solo arranca el servidor HTTP.

En `game/server/`, `main_server.gd` es el punto de entrada headless (abre el `ENetMultiplayerPeer` en el puerto 9000 y delega las conexiones/desconexiones en `RoomManager`); `room_manager.gd` mantiene el diccionario `salas_activas` (`sala_id → MotorDeJuego`) y es el único punto que conoce qué módulo de juego corresponde a cada sala; `game_engine/interfaz_comun.gd` define la clase base `MotorDeJuego` que implementan `guinote/`, `mus/` y `tute/` (contrato completo en `analisis_funcional_app.md` §7).

---

## 3. Tecnologías por componente

| Componente | Tecnología | Notas |
|---|---|---|
| Cliente | Godot 4.7, GDScript | Exportado a ejecutable Windows/Linux, no a Web |
| Red cliente ↔ servidor de partida | `ENetMultiplayerPeer` sobre UDP | Sin TLS en este canal (ver §5) |
| Servidor de partida | Godot 4 headless, GDScript | `godot --headless --path game`, puerto 9000 |
| Backend | Node.js + Express | `backend/src/app.js` |
| Base de datos | PostgreSQL 16 | Extensión `pgcrypto` para `gen_random_uuid()` (`migrations/001_init.sql`) |
| Autenticación | JWT (`jsonwebtoken`) + `bcrypt` para contraseñas | Verificado en `backend/src/middleware/auth.js` |
| Proxy inverso / TLS | nginx + Let's Encrypt (Certbot) | Solo delante del backend REST (`infra/nginx/nginx.conf`) |
| Orquestación local/dev | Docker Compose | Levanta `db` + `backend` (`docker-compose.yml`); el cliente y el servidor de partida se ejecutan fuera de Compose (Godot no está dockerizado en este repo) |

---

## 4. Entornos y despliegue

**Desarrollo local:**
1. `docker compose up -d` — levanta `db` (Postgres, puerto expuesto `5432`) y `backend` (puerto `3000`), con `JWT_SECRET` y `DATABASE_URL` de ejemplo en el propio `docker-compose.yml`.
2. `backend/migrations/001_init.sql` se aplica manualmente contra la base de datos (no hay migrador automático configurado todavía).
3. El servidor de partida y el cliente se lanzan aparte con el editor/CLI de Godot — no están en `docker-compose.yml`.

**Producción (según `infra/nginx/nginx.conf`):**
- nginx expone `api.tudominio.com` en el puerto 443, con certificado TLS de Let's Encrypt, y hace `proxy_pass` a `backend:3000`. El puerto 80 solo redirige a HTTPS.
- El servidor de partida no está detrás de nginx: el cliente se conecta directamente por ENet/UDP a la `servidor_direccion` (`host:puerto`) que el backend le entrega al completarse una sala (contrato en `analisis_funcional_app.md` §5).
- No hay todavía definición de cómo se orquesta el servidor de partida en producción (una instancia por sala, un pool, reinicio ante caída, etc.) ni de balanceo entre varias instancias del backend — pendiente de decidir cuando el equipo aborde el despliegue real.

---

## 5. Límites de confianza y seguridad

- **Cliente ↔ Backend (REST):** cifrado (HTTPS vía nginx), porque viajan credenciales de login. Autenticación por JWT en `Authorization: Bearer <token>` en todas las rutas salvo registro/login/listado de salas/ranking (ver `analisis_funcional_app.md` §5).
- **Cliente ↔ Servidor de partida (ENet/UDP):** sin TLS — decisión de equipo, ya que es un juego por turnos y no hay credenciales viajando por ese canal (la identidad ya se valida en `unirse_partida` con el token obtenido del login).
- **Servidor de partida ↔ Backend (HTTP interno):** ruta `POST /interno/partidas`, protegida por un secreto compartido servidor-a-servidor (no JWT de usuario) mandado en la cabecera `X-Internal-Secret`. Solo la invoca el servidor de partida, nunca el cliente. El secreto vive en la variable de entorno `INTERNAL_API_SECRET` (ya definida en `backend/.env.example` y `docker-compose.yml`); el servidor de partida debe leer el mismo valor de su propia configuración cuando se implemente esa llamada.
- **Contraseñas:** cifradas con `bcrypt` antes de guardarse (`usuarios.password_hash`).
- El backend no confía en ningún dato de estado de partida que no venga de esa ruta interna — el backend no valida reglas de juego, solo persiste lo que le informa el servidor de partida.

---

## 6. Escalado y requisitos no funcionales relevantes para la arquitectura

Recordatorio de los NFR que condicionan decisiones de arquitectura (fuente completa: informe de la Práctica 1, §4 Definición de Hecho):

- Tiempo de respuesta de las acciones de juego: < 500 ms → motiva UDP/ENet en vez de HTTP para el canal de partida.
- Mínimo de partidas simultáneas sin degradación: 5 → cada partida corre dentro del mismo proceso headless de Godot vía `RoomManager`; no hay todavía criterio de cuándo pasar a múltiples procesos/instancias.
- Compatibilidad: Windows 10/11 y una distribución Linux común → condiciona que el cliente se exporte como ejecutable nativo por plataforma, no como un único binario multiplataforma.

---

## 7. Cómo mantener esto sincronizado

- Si cambia un componente, un puerto, una tecnología o un límite de confianza, se actualiza este archivo en el mismo Pull Request.
- Los contratos detallados (API, protocolo de red, modelo de datos, reglas de juego) se mantienen únicamente en `analisis_funcional_app.md` — este documento solo referencia las secciones relevantes, no las repite.
- Pendiente: diagrama exportado en `diagramas/arquitectura.png`, y decisión de despliegue/orquestación del servidor de partida en producción (§4).
