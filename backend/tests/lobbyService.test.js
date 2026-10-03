jest.mock("../src/models/db", () => ({ query: jest.fn(), connect: jest.fn() }));

const pool = require("../src/models/db");
const lobbyService = require("../src/services/lobbyService");

const SALA_ID = "11111111-1111-4111-8111-111111111111";
const USUARIO_ID = "22222222-2222-4222-8222-222222222222";
const OTRO_ID = "33333333-3333-4333-8333-333333333333";

let cliente;

// Enruta las consultas del cliente transaccional según el SQL, sin depender del orden.
function prepararCliente(respuestas = {}) {
  cliente = {
    query: jest.fn(async (sql) => {
      for (const [patron, valor] of Object.entries(respuestas)) {
        if (sql.includes(patron)) {
          if (valor instanceof Error) throw valor;
          return { rows: valor };
        }
      }
      return { rows: [] };
    }),
    release: jest.fn(),
  };
  pool.connect.mockResolvedValue(cliente);
}

function sqlsEjecutados() {
  return cliente.query.mock.calls.map(([sql]) => sql.trim());
}

beforeEach(() => {
  jest.clearAllMocks();
  process.env.GAME_SERVER_ADDRESS = "localhost:9000";
});

describe("lobbyService.listarSalas", () => {
  it("devuelve las salas en espera sin filtrar cuando no se pasa juego", async () => {
    const salas = [{ id: SALA_ID, juego: "guinote", jugadores_actuales: 2 }];
    pool.query.mockResolvedValueOnce({ rows: salas });

    const resultado = await lobbyService.listarSalas({});

    expect(resultado).toEqual(salas);
    const [sql, params] = pool.query.mock.calls[0];
    expect(sql).toContain("estado = 'esperando'");
    expect(params).toEqual([null]);
  });

  it("filtra por juego cuando se indica", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    await lobbyService.listarSalas({ juego: "guinote" });

    expect(pool.query.mock.calls[0][1]).toEqual(["guinote"]);
  });

  it("rechaza un juego desconocido sin consultar la base de datos", async () => {
    await expect(
      lobbyService.listarSalas({ juego: "poker" }),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.query).not.toHaveBeenCalled();
  });
});

describe("lobbyService.crearSala", () => {
  it("crea la sala de 4 plazas y sienta al creador en la posición 0, en una transacción", async () => {
    prepararCliente({
      "INSERT INTO salas": [
        { id: SALA_ID, juego: "guinote", estado: "esperando", capacidad: 4 },
      ],
    });

    const sala = await lobbyService.crearSala({ juego: "guinote" }, USUARIO_ID);

    expect(sala).toEqual({
      id: SALA_ID,
      juego: "guinote",
      estado: "esperando",
      capacidad: 4,
      servidor_direccion: "localhost:9000",
    });
    expect(sqlsEjecutados()).toEqual([
      "BEGIN",
      expect.stringContaining("INSERT INTO salas"),
      expect.stringContaining("INSERT INTO sala_participantes"),
      "COMMIT",
    ]);
    const insertParticipante = cliente.query.mock.calls[2];
    expect(insertParticipante[1]).toEqual([SALA_ID, USUARIO_ID]);
    expect(cliente.release).toHaveBeenCalledTimes(1);
  });

  it("rechaza juegos que todavía no se pueden crear, sin abrir transacción", async () => {
    await expect(
      lobbyService.crearSala({ juego: "mus" }, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("hace ROLLBACK y libera el cliente si falla un insert", async () => {
    prepararCliente({
      "INSERT INTO sala_participantes": new Error("fallo de BD"),
      "INSERT INTO salas": [
        { id: SALA_ID, juego: "guinote", estado: "esperando", capacidad: 4 },
      ],
    });

    await expect(
      lobbyService.crearSala({ juego: "guinote" }, USUARIO_ID),
    ).rejects.toThrow("fallo de BD");
    expect(sqlsEjecutados()).toContain("ROLLBACK");
    expect(sqlsEjecutados()).not.toContain("COMMIT");
    expect(cliente.release).toHaveBeenCalledTimes(1);
  });
});

describe("lobbyService.unirseSala", () => {
  const salaEsperando = {
    id: SALA_ID,
    juego: "guinote",
    estado: "esperando",
    capacidad: 4,
    creador_id: OTRO_ID,
  };

  it("asigna la primera posición libre y devuelve la sala con el recuento actualizado", async () => {
    prepararCliente({
      "FROM salas WHERE id": [salaEsperando],
      "FROM sala_participantes WHERE sala_id": [
        { usuario_id: OTRO_ID, posicion: 0 },
        { usuario_id: "44444444-4444-4444-8444-444444444444", posicion: 2 },
      ],
    });

    const sala = await lobbyService.unirseSala(SALA_ID, USUARIO_ID);

    expect(sala).toEqual({
      id: SALA_ID,
      juego: "guinote",
      estado: "esperando",
      capacidad: 4,
      creador_id: OTRO_ID,
      jugadores_actuales: 3,
    });
    const insert = cliente.query.mock.calls.find(([sql]) =>
      sql.includes("INSERT INTO sala_participantes"),
    );
    expect(insert[1]).toEqual([SALA_ID, USUARIO_ID, 1]);
    expect(sqlsEjecutados()).toContain("COMMIT");
  });

  it("bloquea la fila de la sala con FOR UPDATE", async () => {
    prepararCliente({ "FROM salas WHERE id": [salaEsperando] });

    await lobbyService.unirseSala(SALA_ID, USUARIO_ID).catch(() => {});

    expect(
      sqlsEjecutados().find((sql) => sql.includes("FROM salas")),
    ).toContain("FOR UPDATE");
  });

  it("rechaza un id que no es UUID sin tocar la base de datos", async () => {
    await expect(
      lobbyService.unirseSala("no-es-uuid", USUARIO_ID),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("404 si la sala no existe", async () => {
    prepararCliente({ "FROM salas WHERE id": [] });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 404,
    });
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("409 si la sala ya no está en espera", async () => {
    prepararCliente({
      "FROM salas WHERE id": [{ ...salaEsperando, estado: "en_curso" }],
    });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 409,
    });
  });

  it("409 si el usuario ya está sentado en la sala", async () => {
    prepararCliente({
      "FROM salas WHERE id": [salaEsperando],
      "FROM sala_participantes WHERE sala_id": [
        { usuario_id: USUARIO_ID, posicion: 0 },
      ],
    });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 409,
      message: "ya estás en esta sala",
    });
  });

  it("409 si no quedan plazas libres", async () => {
    prepararCliente({
      "FROM salas WHERE id": [salaEsperando],
      "FROM sala_participantes WHERE sala_id": [
        { usuario_id: "a", posicion: 0 },
        { usuario_id: "b", posicion: 1 },
        { usuario_id: "c", posicion: 2 },
        { usuario_id: "d", posicion: 3 },
      ],
    });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 409,
      message: "la sala está llena",
    });
    expect(
      sqlsEjecutados().some((sql) =>
        sql.includes("INSERT INTO sala_participantes"),
      ),
    ).toBe(false);
  });
});
