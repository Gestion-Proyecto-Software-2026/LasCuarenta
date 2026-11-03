jest.mock("../src/models/db", () => ({ query: jest.fn(), connect: jest.fn() }));

const pool = require("../src/models/db");
const internoService = require("../src/services/internoService");

const SALA_ID = "11111111-1111-4111-8111-111111111111";
const USUARIO_ID = "22222222-2222-4222-8222-222222222222";

let cliente;

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

beforeEach(() => {
  jest.clearAllMocks();
});

describe("internoService.obtenerSala", () => {
  it("devuelve la sala con los participantes y su equipo calculado", async () => {
    pool.query
      .mockResolvedValueOnce({
        rows: [
          { id: SALA_ID, juego: "guinote", estado: "esperando", capacidad: 4 },
        ],
      })
      .mockResolvedValueOnce({
        rows: [
          { usuario_id: USUARIO_ID, posicion: 0 },
          { usuario_id: "otro", posicion: 1 },
        ],
      });

    const sala = await internoService.obtenerSala(SALA_ID);

    expect(sala).toEqual({
      id: SALA_ID,
      juego: "guinote",
      estado: "esperando",
      capacidad: 4,
      participantes: [
        { usuario_id: USUARIO_ID, posicion: 0, equipo: 0 },
        { usuario_id: "otro", posicion: 1, equipo: 1 },
      ],
    });
  });

  it("404 si la sala no existe", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    await expect(internoService.obtenerSala(SALA_ID)).rejects.toMatchObject({
      status: 404,
    });
  });

  it("400 si el id no es un UUID", async () => {
    await expect(
      internoService.obtenerSala("no-es-uuid"),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.query).not.toHaveBeenCalled();
  });
});

describe("internoService.registrarPartida", () => {
  const jugadores = [
    { usuario_id: USUARIO_ID, posicion: 0, equipo: 0 },
    { usuario_id: "otro", posicion: 1, equipo: 1 },
  ];
  const resultado = { equipo_ganador: 0, puntos_por_equipo: [101, 54] };

  it("inserta la partida, a cada jugador y cierra la sala, en una transacción", async () => {
    const PARTIDA_ID = "33333333-3333-4333-8333-333333333333";
    prepararCliente({
      "FROM salas WHERE id": [{ id: SALA_ID, juego: "guinote" }],
      "INSERT INTO partidas": [{ id: PARTIDA_ID }],
    });

    const partida = await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado,
    });

    expect(partida).toEqual({ id: PARTIDA_ID });

    const sqls = cliente.query.mock.calls.map(([sql]) => sql.trim());
    expect(sqls[0]).toBe("BEGIN");
    expect(sqls.at(-1)).toBe("COMMIT");
    expect(
      sqls.some((s) => s.includes("UPDATE salas SET estado = 'finalizada'")),
    ).toBe(true);

    const insertsJugador = cliente.query.mock.calls.filter(([sql]) =>
      sql.includes("INSERT INTO partida_jugadores"),
    );
    expect(insertsJugador).toHaveLength(2);
    expect(insertsJugador[0][1]).toEqual([
      PARTIDA_ID,
      USUARIO_ID,
      0,
      101,
      true,
    ]);
    expect(insertsJugador[1][1]).toEqual([PARTIDA_ID, "otro", 1, 54, false]);
    expect(cliente.release).toHaveBeenCalledTimes(1);
  });

  it("404 si la sala no existe, y hace ROLLBACK", async () => {
    prepararCliente({ "FROM salas WHERE id": [] });

    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado,
      }),
    ).rejects.toMatchObject({ status: 404 });

    expect(cliente.query.mock.calls.map(([sql]) => sql.trim())).toContain(
      "ROLLBACK",
    );
  });

  it("400 si falta resultado.equipo_ganador, sin abrir transacción", async () => {
    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado: {},
      }),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("400 si jugadores no es un array", async () => {
    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores: null,
        resultado,
      }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("400 si sala_id no es un UUID", async () => {
    await expect(
      internoService.registrarPartida({ sala_id: "x", jugadores, resultado }),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });
});
