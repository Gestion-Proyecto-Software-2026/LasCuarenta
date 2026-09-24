# Cartas Online — Guiñote, Mus y Tute

Aplicación de escritorio (Windows/Linux) para jugar Guiñote, Mus y Tute online.
Proyecto de la asignatura Gestión de Proyectos Software.

## Decisiones técnicas clave
- Motor de juego: Godot 4, **GDScript** (no C# — decisión de equipo, no limitación técnica; ver `docs/analisis_funcional_app.md` §2).
- Red multijugador: **ENetMultiplayerPeer** (no WebSocket — no hay cliente Web en esta variante).
- Backend transaccional: Node.js + Express + PostgreSQL.

**Antes de tocar código, leer `docs/analisis_funcional_app.md`.** Es el contrato compartido (modelo de datos, API, protocolo de red, reglas de cada juego) para que todo el equipo —y sus asistentes de IA— construyan contra lo mismo.

## Estructura del repositorio
- `backend/` — API REST (Node.js + Express + PostgreSQL).
- `game/` — proyecto Godot:
  - `client/` — solo presentación e input. Nunca decide el estado del juego.
  - `server/` — lógica autoritativa. Ningún script aquí debe heredar de un nodo visual.
  - `shared/` — lo que ambos necesitan sin duplicar.
  - `tests/` — tests GUT (`addons/gut/` es el framework).
- `infra/` — configuración de despliegue (nginx + TLS delante del backend).
- `docs/` — documentación técnica y de arquitectura.

## Primeros pasos
Hace falta Docker, Godot 4.7 y, para trabajar en el backend fuera de Docker, Node.js 20.12 o superior.

1. **Backend y base de datos:** `docker compose up -d`. Levanta PostgreSQL (puerto 5432) y el backend (puerto 3000), y la primera vez crea las tablas solo. Comprobación: `http://localhost:3000/health` responde `{"ok":true}`.
2. **Servidor de partida**, con los mismos secretos que `docker-compose.yml` (sin ellos no arranca):
   ```bash
   JWT_SECRET=cambia_esto_en_produccion INTERNAL_API_SECRET=cambia_esto_tambien_en_produccion godot --headless --path game res://server/main_server.tscn
   ```
3. **Cliente:** abrir `game/project.godot` en el editor de Godot 4.7.
4. **Tests:** `godot --headless --path game -s addons/gut/gut_cmdln.gd` para el juego (o el panel de GUT en el editor); `npm ci` y `npm test` dentro de `backend/` para el backend.

Para arrancar el backend fuera de Docker (`npm run dev` en `backend/`), copiar `backend/.env.example` a `backend/.env` y ajustar valores. Más detalle en `docs/arquitectura.md` §4.

## Reglas no negociables (ver `docs/analisis_funcional_app.md` §2)
- GDScript, no C#.
- `ENetMultiplayerPeer`, no `WebSocketMultiplayerPeer`.
- Ninguna Pull Request se fusiona a `main` sin revisión de otra persona del equipo.
