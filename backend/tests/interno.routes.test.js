jest.mock("../src/services/internoService", () => ({
  obtenerSala: jest.fn(),
  registrarPartida: jest.fn(),
}));

const request = require("supertest");
const app = require("../src/app");
const internoService = require("../src/services/internoService");
const { ErrorHttp } = require("../src/utils/errorHttp");

const SALA_ID = "11111111-1111-4111-8111-111111111111";
const SECRETO = "secreto_interno_de_test";

beforeAll(() => {
  process.env.INTERNAL_API_SECRET = SECRETO;
});

beforeEach(() => jest.clearAllMocks());

describe("GET /api/interno/salas/:id", () => {
  it("401 si falta la cabecera X-Internal-Secret", async () => {
    const res = await request(app).get(`/api/interno/salas/${SALA_ID}`);
    expect(res.status).toBe(401);
    expect(internoService.obtenerSala).not.toHaveBeenCalled();
  });

  it("401 si la cabecera no coincide", async () => {
    const res = await request(app)
      .get(`/api/interno/salas/${SALA_ID}`)
      .set("X-Internal-Secret", "incorrecto");
    expect(res.status).toBe(401);
  });

  it("200 con la sala cuando el secreto coincide", async () => {
    internoService.obtenerSala.mockResolvedValue({
      id: SALA_ID,
      juego: "guinote",
      estado: "esperando",
      capacidad: 4,
      participantes: [],
    });

    const res = await request(app)
      .get(`/api/interno/salas/${SALA_ID}`)
      .set("X-Internal-Secret", SECRETO);

    expect(res.status).toBe(200);
    expect(res.body.id).toBe(SALA_ID);
    expect(internoService.obtenerSala).toHaveBeenCalledWith(SALA_ID);
  });

  it("404 si la sala no existe", async () => {
    internoService.obtenerSala.mockRejectedValue(
      new ErrorHttp(404, "la sala no existe"),
    );

    const res = await request(app)
      .get(`/api/interno/salas/${SALA_ID}`)
      .set("X-Internal-Secret", SECRETO);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "la sala no existe" });
  });
});

describe("POST /api/interno/partidas", () => {
  const body = {
    sala_id: SALA_ID,
    jugadores: [{ usuario_id: "u1", posicion: 0, equipo: 0 }],
    resultado: { equipo_ganador: 0, puntos_por_equipo: [101, 54] },
  };

  it("401 sin el secreto interno", async () => {
    const res = await request(app).post("/api/interno/partidas").send(body);
    expect(res.status).toBe(401);
    expect(internoService.registrarPartida).not.toHaveBeenCalled();
  });

  it("201 cuando el secreto coincide", async () => {
    internoService.registrarPartida.mockResolvedValue({ id: "partida-1" });

    const res = await request(app)
      .post("/api/interno/partidas")
      .set("X-Internal-Secret", SECRETO)
      .send(body);

    expect(res.status).toBe(201);
    expect(res.body).toEqual({ id: "partida-1" });
    expect(internoService.registrarPartida).toHaveBeenCalledWith(body);
  });

  it("400 si el body está mal formado", async () => {
    internoService.registrarPartida.mockRejectedValue(
      new ErrorHttp(400, "resultado es obligatorio"),
    );

    const res = await request(app)
      .post("/api/interno/partidas")
      .set("X-Internal-Secret", SECRETO)
      .send({ sala_id: SALA_ID });

    expect(res.status).toBe(400);
  });
});
