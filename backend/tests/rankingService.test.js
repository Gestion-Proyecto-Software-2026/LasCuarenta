jest.mock("../src/models/db", () => ({ query: jest.fn() }));

const pool = require("../src/models/db");
const rankingService = require("../src/services/rankingService");

beforeEach(() => {
  jest.clearAllMocks();
  pool.query.mockResolvedValue({ rows: [] });
});

describe("rankingService.obtenerRanking", () => {
  it("devuelve las filas tal cual las ordena la consulta", async () => {
    const filas = [
      {
        usuario_id: "a",
        nombre_visible: "Ana",
        puntos_totales: 300,
        posicion: 1,
      },
      {
        usuario_id: "b",
        nombre_visible: "Bea",
        puntos_totales: 120,
        posicion: 2,
      },
    ];
    pool.query.mockResolvedValue({ rows: filas });

    expect(await rankingService.obtenerRanking({ juego: "guinote" })).toEqual(
      filas,
    );
  });

  it("filtra por juego y aplica el límite por defecto", async () => {
    await rankingService.obtenerRanking({ juego: "mus" });

    const [sql, params] = pool.query.mock.calls[0];
    expect(params).toEqual(["mus", 100]);
    expect(sql).toMatch(/FROM partida_jugadores/);
    expect(sql).toMatch(/SUM\(pj\.puntos_obtenidos\)/);
    expect(sql).toMatch(/ORDER BY puntos_totales DESC/);
  });

  it("sin juego agrega todos los juegos", async () => {
    await rankingService.obtenerRanking();

    expect(pool.query.mock.calls[0][1]).toEqual([null, 100]);
  });

  it("acepta un límite válido en texto (query string)", async () => {
    await rankingService.obtenerRanking({ limite: "10" });

    expect(pool.query.mock.calls[0][1]).toEqual([null, 10]);
  });

  it.each(["0", "501", "abc", "2.5"])("400 con límite %s", async (limite) => {
    await expect(
      rankingService.obtenerRanking({ limite }),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.query).not.toHaveBeenCalled();
  });

  it("400 con un juego no admitido", async () => {
    await expect(
      rankingService.obtenerRanking({ juego: "poker" }),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.query).not.toHaveBeenCalled();
  });
});
