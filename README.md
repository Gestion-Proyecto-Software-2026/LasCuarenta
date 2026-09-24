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
- `infra/` — configuración de despliegue (nginx + TLS delante del backend).
- `docs/` — documentación técnica y de arquitectura.

## Primeros pasos
1. Copiar `backend/.env.example` a `backend/.env` y ajustar valores.
2. `docker compose up -d` — levanta backend + PostgreSQL.
3. Ejecutar `backend/migrations/001_init.sql` contra la base de datos.
4. Abrir `game/project.godot` en el editor de Godot 4.7.

## Reglas no negociables (ver `docs/analisis_funcional_app.md` §2)
- GDScript, no C#.
- `ENetMultiplayerPeer`, no `WebSocketMultiplayerPeer`.
- Ninguna Pull Request se fusiona a `main` sin revisión de otra persona del equipo.
