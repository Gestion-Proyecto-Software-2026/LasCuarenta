jest.mock("../src/services/rankingService", () => ({
  obtenerRanking: jest.fn(),
}));

const request = require("supertest");
const app = require("../src/app");
const rankingService = require("../src/services/rankingService");
const { ErrorHttp } = require("../src/utils/errorHttp");

beforeEach(() => {
  jest.clearAllMocks();
});

describe("GET /api/ranking", () => {
  it("200 sin token: la clasificación es pública", async () => {
    const ranking = [
      {
        usuario_id: "u1",
        nombre_visible: "Ana",
        puntos_totales: 250,
        partidas_jugadas: 3,
        partidas_ganadas: 2,
        posicion: 1,
      },
    ];
    rankingService.obtenerRanking.mockResolvedValue(ranking);

    const res = await request(app).get("/api/ranking?juego=guinote");

    expect(res.status).toBe(200);
    expect(res.body).toEqual(ranking);
    expect(rankingService.obtenerRanking).toHaveBeenCalledWith({
      juego: "guinote",
    });
  });

  it("400 si el servicio rechaza el juego", async () => {
    rankingService.obtenerRanking.mockRejectedValue(
      new ErrorHttp(400, "juego no válido"),
    );

    const res = await request(app).get("/api/ranking?juego=poker");

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "juego no válido" });
  });

  it("500 ante un error inesperado", async () => {
    rankingService.obtenerRanking.mockRejectedValue(new Error("bd caída"));
    jest.spyOn(console, "error").mockImplementation(() => {});

    const res = await request(app).get("/api/ranking");

    expect(res.status).toBe(500);
    console.error.mockRestore();
  });
});
