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

## 4. Antes de abrir un PR

Checklist resumido de la Definición de Hecho (fuente completa: informe de la Práctica 1 entregado, §4):

- [ ] Tests automáticos (unitarios y de integración) pasan en CI.
- [ ] Cobertura de tests de la lógica de juego ≥ 60%.
- [ ] Documentación (`README`/`docs/`) actualizada si la PBI la afecta.
- [ ] Backend formateado con Prettier.
- [ ] GDScript sigue la [guía de estilo oficial de Godot](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).
- [ ] Funcionalidad probada en el entorno de pruebas.

## 5. Estructura de carpetas (recordatorio)

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
