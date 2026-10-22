# Cartas Online — Guiñote, Mus y Tute

Aplicación de escritorio (Windows y Linux) para jugar online a tres juegos de baraja española: **Guiñote**, **Mus** y **Tute**. Proyecto de la asignatura Gestión de Proyectos Software.

> **Antes de tocar código, leed [`docs/analisis_funcional_app.md`](docs/analisis_funcional_app.md).** Es el contrato compartido del equipo: modelo de datos, API REST, protocolo de red, interfaz de los motores y reglas de cada juego. Si una IA o una persona propone algo distinto, se corrige contra ese documento. Este README resume y enlaza; no lo sustituye.

## Índice

1. [Estado del proyecto](#1-estado-del-proyecto)
2. [Arquitectura](#2-arquitectura)
3. [Estructura del repositorio](#3-estructura-del-repositorio)
4. [Requisitos](#4-requisitos)
5. [Puesta en marcha en local](#5-puesta-en-marcha-en-local)
6. [Variables de entorno](#6-variables-de-entorno)
7. [Tests y calidad](#7-tests-y-calidad)
8. [Cómo funciona una partida](#8-cómo-funciona-una-partida)
9. [Los juegos](#9-los-juegos)
10. [Cómo se trabaja en el equipo](#10-cómo-se-trabaja-en-el-equipo)
11. [Integración continua y versiones](#11-integración-continua-y-versiones)
12. [Despliegue en producción](#12-despliegue-en-producción)
13. [Documentación](#13-documentación)
14. [Licencia](#14-licencia)

---

## 1. Estado del proyecto

La pila del producto tiene 9 PBI (talla y prioridad según la Práctica 1). Cada una se sigue en su Issue de GitHub.

| PBI | Prioridad | Estado |
|---|---|---|
| PBI-01 — Registro y autenticación | Alta | ✅ Backend (registro, login, recuperar y restablecer contraseña) y pantallas del cliente |
| PBI-02 — Lobby y gestión de salas | Alta | ✅ Listar, crear y unirse a salas, en el backend y en el cliente. Solo se pueden crear salas de Guiñote |
| PBI-03 — Partida completa de Guiñote | Alta | ✅ Motor de reglas completo y registrado en el servidor de partida |
| PBI-04 — Partida completa de Mus | Media | 🟡 Motor de reglas completo (2 o 4 jugadores) y registrado; falta poder crear salas de Mus y jugarlas desde el cliente |
| PBI-05 — Partida completa de Tute | Media | ⏳ Pendiente |
| PBI-06 — Historial y estadísticas | Media | ⏳ Pendiente (la ruta existe y responde `501`) |
| PBI-07 — Ranking de jugadores | Baja | ⏳ Pendiente (la ruta existe y responde `501`) |
| PBI-08 — Chat en partida | Baja | ⏳ Pendiente (el servidor responde que el chat no está disponible) |
| PBI-09 — Moderación de salas | Baja | ⏳ Pendiente (`POST /salas/:id/expulsar` responde `501`) |

**Todavía no se puede jugar una partida de principio a fin desde el cliente.** Los motores de Guiñote y Mus funcionan y están probados, pero faltan piezas que no pertenecen a ninguna PBI de juego:

- **Rutas internas del backend.** `GET /interno/salas/:id` y `POST /interno/partidas` están en el contrato (§5) y el servidor de partida ya las llama, pero el backend aún no las implementa. Sin ellas, el servidor de partida no puede cargar salas ni guardar resultados.
- **Conexión del cliente con el servidor de partida.** El cliente no abre todavía la conexión ENet ni envía `unirse_partida` cuando la sala se completa. Tampoco hay mesa de juego: `client/scenes/mesa/tapete.tscn` es solo un esqueleto.
- **Salas de Mus.** `POST /salas` solo admite `guinote` (capacidad 4). Falta `mus` con capacidad 2 o 4.

---

## 2. Arquitectura

Tres piezas con responsabilidades separadas (detalle en [`docs/arquitectura.md`](docs/arquitectura.md)):

- **Cliente** — proyecto Godot (GDScript) exportado a ejecutable nativo. Solo pinta lo que le dice el servidor y recoge el input: **nunca decide si una jugada es válida**.
- **Backend REST** — Node.js + Express + PostgreSQL. Todo lo transaccional: cuentas, lobby y salas, historial, ranking. No sabe nada de las reglas de los juegos.
- **Servidor de partida** — Godot headless (GDScript). Es la **autoridad única** sobre el estado de cada partida en curso. Habla con los clientes por ENet (UDP) y notifica el resultado final al backend por HTTP interno.

```text
Cliente (Godot nativo) ──HTTPS REST──▶ nginx ──▶ Backend (Node+Express) ──SQL──▶ PostgreSQL
        │                                                ▲
        │                                                │ HTTP interno (X-Internal-Secret)
        └────────ENet (UDP)────────▶ Servidor de partida ┘
                                     (Godot headless: RoomManager + MotorDeJuego)
```

Tecnologías por componente:

| Componente | Tecnología |
|---|---|
| Cliente | Godot 4.7, GDScript, exportado a Windows y Linux (no a Web) |
| Red cliente ↔ servidor de partida | `ENetMultiplayerPeer` sobre UDP, puerto 9000 por defecto, sin TLS |
| Servidor de partida | Godot 4.7 headless, GDScript |
| Backend | Node.js ≥ 20.12, Express |
| Base de datos | PostgreSQL 16 (extensión `pgcrypto`) |
| Autenticación | JWT (`jsonwebtoken`) y `bcrypt` |
| Correo (recuperar contraseña) | `nodemailer` por SMTP |
| Proxy inverso y TLS | nginx con Let's Encrypt, solo delante del backend |
| Entorno local | Docker Compose (base de datos y backend) |

### Decisiones no negociables

Ya están tomadas ([`docs/analisis_funcional_app.md`](docs/analisis_funcional_app.md) §2). Si alguien o alguna IA propone otra cosa, se corrige contra el documento:

- **GDScript, no C#.** Es una convención de equipo, no un límite técnico.
- **`ENetMultiplayerPeer`, no `WebSocketMultiplayerPeer`.** No hay cliente Web.
- **Estilo de código.** GDScript sigue la [guía oficial de Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) (`snake_case` y `PascalCase`); el backend usa `camelCase` y se formatea con Prettier.
- **Ninguna Pull Request entra en `main` sin la revisión de otra persona del equipo.**

### Requisitos no funcionales

La fuente es la Definición de Hecho de la Práctica 1:

- Las acciones de juego responden en menos de 500 ms.
- Funciona en Windows 10/11 y en una distribución Linux común (p. ej. Ubuntu LTS).
- La lógica de juego tiene una cobertura de tests ≥ 60 %.
- Se soportan al menos 5 partidas simultáneas sin degradación.
- Las contraseñas se guardan cifradas.

---

## 3. Estructura del repositorio

```text
.
├── backend/                 API REST (Node.js + Express + PostgreSQL)
│   ├── src/
│   │   ├── app.js           monta las rutas bajo /api y expone /health y /api/docs
│   │   ├── index.js         arranca el servidor HTTP (carga backend/.env si existe)
│   │   ├── routes/          un fichero por recurso: auth, lobby, historial, ranking
│   │   ├── services/        lógica de cada recurso (authService, lobbyService)
│   │   ├── middleware/      auth.js = verificación del JWT
│   │   ├── models/db.js     pool de conexión a PostgreSQL (único punto de acceso)
│   │   └── utils/           errores HTTP y envío de correo
│   ├── migrations/          SQL que crea y endurece el esquema (001, 002, 003…)
│   ├── tests/               Jest + Supertest
│   └── openapi.yaml         especificación de la API que se sirve en /api/docs
├── game/                    proyecto Godot (abrir game/project.godot)
│   ├── client/              solo presentación e input
│   │   ├── autoload/        ClienteApi (REST + JWT), FuncionesGlobales
│   │   ├── ui/              login, registro, recuperar, lobby, tema visual
│   │   └── scenes/          carta, mesa (cada escena en su carpeta, junto a su script)
│   ├── server/              lógica autoritativa; ningún script hereda de un nodo visual
│   │   ├── main_server.*    punto de entrada headless, abre ENet y registra los motores
│   │   ├── room_manager.gd  salas en memoria, validación de unirse_partida y jugadas
│   │   ├── sala_activa.gd   una sala: asientos, conexiones y estado de su partida
│   │   ├── verificador_jwt.gd, cliente_backend.gd
│   │   └── game_engine/     MotorDeJuego (clase base) + guinote/, mus/, tute/
│   ├── shared/              Carta, Baraja, CanalRed (RPC único) y MensajesRed
│   ├── tests/               tests GUT: unit/ (refleja la ruta del script) e integration/
│   └── addons/gut/          framework de testing GUT
├── infra/nginx/             proxy inverso con TLS delante del backend
├── docs/                    análisis funcional, arquitectura, diagramas
├── docker-compose.yml       PostgreSQL + backend para desarrollo
└── CONTRIBUTING.md          flujo de ramas, Pull Requests y Definición de Hecho
```

---

## 4. Requisitos

| Herramienta | Versión | Para qué |
|---|---|---|
| [Docker](https://docs.docker.com/get-docker/) con Docker Compose | cualquiera reciente | Levantar PostgreSQL y el backend |
| [Godot](https://godotengine.org/download/archive/4.7.2-stable/) | **4.7.2**, versión estándar (sin .NET) | Editor del cliente, servidor de partida y tests GUT. Es la versión del CI |
| [Node.js](https://nodejs.org/) | **≥ 20.12** | Solo para trabajar en el backend fuera de Docker y para pasar sus tests |
| Git | — | — |

En los comandos de este README, `godot` es el ejecutable de Godot 4.7.2. En Windows, usad la variante `_console.exe` para ver la salida en la terminal, p. ej. `Godot_v4.7.2-stable_win64_console.exe`.

---

## 5. Puesta en marcha en local

Son tres procesos: base de datos y backend (Docker), servidor de partida (Godot headless) y cliente (Godot).

### 5.1 Backend y base de datos

```bash
docker compose up -d
```

- Levanta `db` (PostgreSQL, puerto `5432`) y `backend` (puerto `3000`).
- La primera vez, PostgreSQL ejecuta solo las migraciones de `backend/migrations/` y crea las tablas.

Comprobaciones:

- `http://localhost:3000/health` responde `{"ok":true}`.
- `http://localhost:3000/api/docs` muestra la documentación interactiva de la API (Swagger, generada desde `backend/openapi.yaml`).

**Migraciones nuevas.** Solo se ejecutan solas cuando el volumen de la base de datos está vacío. Con un volumen que ya existe, aplicadlas a mano:

```bash
docker compose exec -T db psql -U cartas -d cartas_online < backend/migrations/003_salas_lobby.sql
```

O empezad de cero (⚠️ **borra todos los datos**):

```bash
docker compose down -v && docker compose up -d
```

**Ver los logs del backend:** `docker compose logs -f backend`. **Pararlo todo:** `docker compose down`.

#### Backend fuera de Docker (para desarrollar en él)

```bash
cd backend
cp .env.example .env    # y ajustad los valores (sección 6)
npm ci
npm run dev             # nodemon: reinicia al guardar
```

`src/index.js` carga `backend/.env` al arrancar; las variables que ya existan en el entorno tienen prioridad. La base de datos puede seguir en Docker: `docker compose up -d db`.

### 5.2 Servidor de partida

Necesita **los mismos secretos que el backend**: si no, no arranca. Con los valores de `docker-compose.yml`:

**Linux / macOS / Git Bash:**

```bash
JWT_SECRET=cambia_esto_en_produccion \
INTERNAL_API_SECRET=cambia_esto_tambien_en_produccion \
godot --headless --path game res://server/main_server.tscn
```

**Windows (PowerShell):**

```powershell
$env:JWT_SECRET = "cambia_esto_en_produccion"
$env:INTERNAL_API_SECRET = "cambia_esto_tambien_en_produccion"
godot --headless --path game res://server/main_server.tscn
```

Al arrancar escribe `Servidor de partida escuchando en UDP 9000 (backend: …, juegos: [guinote, mus])`.

- **Otro puerto:** añadid `-- --puerto=9001` al final.
- **Otro backend:** `BACKEND_URL` (opcional, por defecto `http://localhost:3000/api`).
- La dirección que el backend entrega a los clientes (`GAME_SERVER_ADDRESS`, por defecto `localhost:9000`) debe apuntar a este proceso.

### 5.3 Cliente

1. Abrid `game/project.godot` con el editor de Godot 4.7.2.
2. **La escena principal (`client/main_client.tscn`) todavía está vacía.** Para probar el cliente, abrid `client/ui/login/login.tscn` y ejecutadla con **F6** (*Ejecutar escena actual*). Desde el login se llega a registro, recuperar contraseña y, tras iniciar sesión, al lobby.
3. El cliente usa `http://localhost:3000/api` como backend. Para apuntar a otro, definid la variable de entorno `BACKEND_URL` antes de abrir Godot.

Para probar con varios jugadores, abrid varias instancias del cliente: en el editor, menú *Depurar → Personalizar instancias de ejecución…* (*Debug → Customize Run Instances…*). Usad una cuenta distinta en cada una.

---

## 6. Variables de entorno

**Backend.** Ejemplo completo en [`backend/.env.example`](backend/.env.example). En Docker, los valores de desarrollo están en `docker-compose.yml`.

| Variable | Ejemplo | Para qué |
|---|---|---|
| `DATABASE_URL` | `postgres://cartas:cartas_dev_password@localhost:5432/cartas_online` | Conexión a PostgreSQL |
| `JWT_SECRET` | `cambia_esto` | Firma de los tokens de login. **Compartido con el servidor de partida** |
| `JWT_EXPIRES_IN` | `24h` | Caducidad del token |
| `INTERNAL_API_SECRET` | `cambia_esto_tambien` | Secreto de las rutas `/interno/*` (cabecera `X-Internal-Secret`). **Compartido con el servidor de partida**; nunca lo usa el cliente |
| `GAME_SERVER_ADDRESS` | `localhost:9000` | `host:puerto` del servidor de partida que se entrega al cliente (`servidor_direccion`) |
| `PORT` | `3000` | Puerto HTTP del backend |
| `BCRYPT_SALT_ROUNDS` | `10` | Coste del `bcrypt` sobre el hash que envía el cliente |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM` | — | Correo de `POST /auth/recuperar`. En desarrollo sirve un SMTP de pruebas (Mailtrap, Ethereal) |
| `RECOVERY_CODE_TTL_MIN` | `15` | Minutos de validez del código de recuperación |

**Servidor de partida.**

| Variable | Obligatoria | Para qué |
|---|---|---|
| `JWT_SECRET` | Sí | Mismo valor que el backend: el servidor verifica él mismo el token de `unirse_partida` |
| `INTERNAL_API_SECRET` | Sí | Mismo valor que el backend: autentica sus llamadas a `/interno/*` |
| `BACKEND_URL` | No | Por defecto `http://localhost:3000/api` |

**Cliente.**

| Variable | Obligatoria | Para qué |
|---|---|---|
| `BACKEND_URL` | No | Por defecto `http://localhost:3000/api` |

⚠️ Los valores de ejemplo son solo para desarrollo. Si `JWT_SECRET` o `INTERNAL_API_SECRET` se filtran desde cualquiera de los dos procesos, hay que cambiarlos en los dos.

---

## 7. Tests y calidad

### Juego (GUT)

Desde la raíz del repositorio, igual que en el CI:

```bash
godot --headless --path game -s addons/gut/gut_cmdln.gd
```

- **Desde el editor:** usad el panel de GUT (abajo).
- **Solo algunos ficheros:** añadid `-gselect=mus`, por ejemplo, para ejecutar solo los que contienen `mus` en el nombre.
- La primera vez en una copia recién clonada, conviene importar el proyecto antes: `godot --headless --path game --import`.

Convenciones ([CONTRIBUTING.md](CONTRIBUTING.md) §5):

- GUT recorre `game/tests/` y sus subcarpetas, y ejecuta los ficheros `test_*.gd` que heredan de `GutTest`.
- Los tests unitarios van en `game/tests/unit/`, reflejando la ruta del script: `server/game_engine/mus/motor_mus.gd` → `tests/unit/server/game_engine/mus/test_motor_mus.gd`.
- Los que combinan varias piezas (p. ej. `RoomManager` con un motor real) van en `game/tests/integration/`.
- La aleatoriedad del reparto se inyecta (`MotorDeJuego.new(rng)`), así que una partida con semilla fija es reproducible.
- **Cobertura mínima del 60 %** en la lógica de juego (`shared/` y `server/game_engine/`), no en el cliente.

### Backend (Jest + Supertest)

```bash
cd backend
npm ci
npm test               # Jest
npm run lint           # ESLint
npm run format:check   # Prettier (el CI falla si no está formateado)
npm run format         # formatea src/ y tests/
```

Hay un fichero de test por recurso en `backend/tests/`. Las pruebas usan Supertest contra `app`, sin levantar un servidor real.

---

## 8. Cómo funciona una partida

Flujo previsto de principio a fin ([`docs/analisis_funcional_app.md`](docs/analisis_funcional_app.md) §11). Los pasos 3 a 6 todavía no funcionan de extremo a extremo (ver la [sección 1](#1-estado-del-proyecto)).

1. **Login.** El usuario abre el cliente e inicia sesión: `POST /api/auth/login`. El cliente envía el **SHA-256 de la contraseña** (`password_hash`), nunca la contraseña en claro, y el backend le aplica además `bcrypt` antes de guardarla.
2. **Lobby.** Ve las salas con `GET /api/salas` y crea una (`POST /api/salas`) o se une a otra (`POST /api/salas/:id/unirse`). Quien crea la sala ocupa la posición 0; al unirse, el backend da la primera posición libre.
3. **Conexión al servidor de partida.** Con la sala completa, el cliente conecta por ENet a `servidor_direccion` y envía `unirse_partida { usuario_id, token, sala_id }`.
4. **Validación.** El servidor verifica el JWT con el mismo `JWT_SECRET` y pide la sala al backend (`GET /api/interno/salas/:id`). Cuando están todos, envía `partida_iniciada`.
5. **Juego.** Cada acción viaja como `{ tipo, payload }` por el único RPC de `CanalRed`. Tras cada acción válida, cada jugador recibe `estado_partida`:
   - lleva su vista filtrada (nunca las cartas de los demás);
   - incluye `jugadas_validas`, la lista de lo que puede hacer en ese momento, para que el cliente active cartas y botones sin conocer las reglas.
6. **Resultado.** Al terminar, todos reciben `partida_terminada`, y el servidor guarda el resultado con `POST /api/interno/partidas`.

**Reconexión.** Si un jugador se desconecta, la partida sigue en memoria. Al volver a enviar `unirse_partida` recupera su asiento y se pone al día.

**Lista de mensajes y payloads:** §6 del análisis funcional. **Interfaz que implementa cada juego** (`MotorDeJuego`): §7.

---

## 9. Los juegos

Cada juego es un motor que hereda de `MotorDeJuego` (`game/server/game_engine/`). `RoomManager` solo habla con esa interfaz: **añadir un juego no toca `room_manager.gd`**, basta con registrar su motor en `MOTORES` de `server/main_server.gd`. El `jugador_id` es la posición en la mesa, y en las mesas de 4 las parejas son 0-2 contra 1-3.

| Juego | Jugadores | Reglas | Estado |
|---|---|---|---|
| **Guiñote** | 4, por parejas | §8 | Completo: reparto, 4 bazas con robo, arrastre, cantes (20 y las 40), Tute de reyes o sotas, cambio del siete, tanteo a 101 con "diez últimas" y vuelta |
| **Mus** | 2 o 4 | §9 | Completo: mus y descartes, lances (Grande, Chica, Pares, Juego o Punto), envites (pasar, envidar, subir, órdago, quiero, no quiero), cobro, amarracos, juegos a 40 piedras, partida al mejor de 3 juegos |
| **Tute** | 4, por parejas | §10 | Pendiente. Las variantes de 2 y 3 jugadores quedan fuera de alcance |

⚠️ **Aviso:**

- La **tabla de valores de las cartas no se comparte** entre Guiñote y Tute: en Guiñote la Sota vale más que el Caballo, y en el Tute al revés.
- El Tute de Guiñote es de **sotas o reyes**; el del Tute, de **caballos o reyes**.

Los puntos que el reglamento dejaba abiertos, y cómo los resuelve cada motor, están en las *notas de implementación* de §8 y §9 (marcados con ⚠️). Están pendientes de que el equipo los confirme.

---

## 10. Cómo se trabaja en el equipo

Resumen de [CONTRIBUTING.md](CONTRIBUTING.md), que es la referencia completa.

- **`main` es la única rama larga.** Está protegida: todo entra por Pull Request con al menos **1 revisión aprobada** de otra persona y el CI en verde. Debe quedar siempre desplegable.
- **Una rama por PBI o tarea, nunca por persona**, creada desde `main` actualizado y borrada al fusionar:
  - el nombre va atado a la PBI, p. ej. `pbi-06-historial-estadisticas`;
  - lo que no es de ninguna PBI lleva un nombre que diga qué es, p. ej. `fix-backend-lockfile` o `chore-mantenimiento`.
- **Las PBI grandes (L/XL) se rompen en subtareas**, cada una con su rama y su PR directa a `main`. Por ejemplo, Mus fue `pbi-04-reparto-y-fase-mus` → `pbi-04-jugadas-y-apuestas` → `pbi-04-cobro-y-fin-partida`. La lista de ramas de cada PBI está en CONTRIBUTING §4.
- **Las PR usan la plantilla del repositorio.** `Closes #N` cierra el Issue de la PBI; si la PR es solo una subtarea, se pone `Parte de #N`.
- **Los contratos cambian en el mismo PR.** Si cambia un campo de la API, un mensaje de red o una regla, se actualiza `docs/analisis_funcional_app.md` en ese mismo PR, no después. Si cambia un componente, un puerto o un límite de confianza, se actualiza `docs/arquitectura.md`.
- **Con una IA:** pasadle el análisis funcional y decidle qué sección es la relevante (p. ej. "implementa X según §9").

**Definición de Hecho** (checklist antes de abrir una PR):

- [ ] Los tests automáticos (unitarios y de integración) pasan en CI.
- [ ] La cobertura de la lógica de juego es ≥ 60 %.
- [ ] La documentación (`README`, `docs/`) está actualizada si la PBI la afecta.
- [ ] El backend está formateado con Prettier (`npm run format`).
- [ ] El GDScript sigue la guía de estilo oficial de Godot. Los ficheros van en `snake_case`, igual que el nombre de la clase (`class_name Baraja` → `baraja.gd`).
- [ ] La funcionalidad se ha probado en el entorno de pruebas.

---

## 11. Integración continua y versiones

Workflows de `.github/workflows/`:

| Workflow | Cuándo se ejecuta | Qué hace |
|---|---|---|
| `Backend CI` (`backend-ci.yml`) | PR y push a `main` que tocan `backend/` | `npm ci`, `npm run lint`, `npm run format:check`, `npm test` con Node 20 |
| `Godot CI` (`godot-ci.yml`) | PR y push a `main` que tocan `game/` | Todos los tests GUT en headless con Godot 4.7.2 |
| `Build and release client` (`godot-release.yml`) | Al subir un tag `v*` | Exporta el cliente para Windows y Linux y publica una GitHub Release con los ejecutables |

**Publicar una versión del cliente.** Las versiones no tienen rama propia: salen de un tag sobre `main`.

```bash
git checkout main && git pull
git tag v0.2.0
git push origin v0.2.0
```

Los presets de exportación están en `game/export_presets.cfg`: `Windows Desktop` → `build/cartas-online-windows.exe` y `Linux` → `build/cartas-online-linux.x86_64`. Para exportar en local hacen falta las plantillas de exportación de Godot 4.7.2:

```bash
cd game
godot --headless --export-release "Windows Desktop" ../build/cartas-online-windows.exe
godot --headless --export-release "Linux" ../build/cartas-online-linux.x86_64
```

---

## 12. Despliegue en producción

Según [`infra/nginx/nginx.conf`](infra/nginx/nginx.conf) y [`docs/arquitectura.md`](docs/arquitectura.md) §4:

- **nginx** expone el backend en `api.tudominio.com:443`, con certificado de Let's Encrypt, y hace `proxy_pass` a `backend:3000`. El puerto 80 solo redirige a HTTPS.
- **El servidor de partida no pasa por nginx.** Los clientes se conectan directamente por ENet/UDP a la dirección de `GAME_SERVER_ADDRESS`.
- Un único proceso del servidor de partida aloja todas las salas, suficiente para el mínimo de 5 partidas simultáneas.
- **Pendiente de decidir:** cómo se orquesta el servidor de partida en producción (una instancia por sala, un pool, reinicio ante caídas) y el balanceo entre varias instancias del backend.

**Límites de confianza:**

- El canal REST va cifrado, porque viajan credenciales.
- El canal ENet no lleva TLS: es un juego por turnos y la identidad se valida con el token en `unirse_partida`.
- Las rutas `/interno/*` solo las llama el servidor de partida, con el secreto compartido.
- El backend no valida reglas de juego: solo guarda lo que le informa el servidor de partida.

---

## 13. Documentación

| Documento | Contenido |
|---|---|
| [`docs/analisis_funcional_app.md`](docs/analisis_funcional_app.md) | **Fuente de verdad:** convenciones (§2), modelo de datos (§4), API REST (§5), protocolo en tiempo real (§6), interfaz de los motores (§7), reglas de Guiñote (§8), Mus (§9) y Tute (§10), flujo completo (§11) |
| [`docs/arquitectura.md`](docs/arquitectura.md) | Componentes, tecnologías, entornos, despliegue, límites de confianza y escalado |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Ramas, Pull Requests, tests y Definición de Hecho |
| [`backend/openapi.yaml`](backend/openapi.yaml) | Especificación OpenAPI que se sirve en `http://localhost:3000/api/docs` |

---

## 14. Licencia

[MIT](LICENSE) © 2026 Gestion-Proyecto-Software-2026.
