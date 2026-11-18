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

  it("pasa al servicio la causa, las fechas y la posicion tal cual llegan", async () => {
    internoService.registrarPartida.mockResolvedValue({ id: "partida-1" });
    const completo = {
      sala_id: SALA_ID,
      jugadores: [
        {
          usuario_id: "22222222-2222-4222-8222-222222222222",
          posicion: 2,
          equipo: 0,
        },
      ],
      resultado: {
        equipo_ganador: 1,
        puntos_por_equipo: [40, 101],
        causa: "renuncio",
        motivo: "tantos",
      },
      fecha_inicio: "2026-11-18T10:00:00Z",
      fecha_fin: "2026-11-18T10:24:13Z",
    };

    const res = await request(app)
      .post("/api/interno/partidas")
      .set("X-Internal-Secret", SECRETO)
      .send(completo);

    expect(res.status).toBe(201);
    expect(internoService.registrarPartida).toHaveBeenCalledWith(completo);
  });

  it("400 con el motivo si un usuario_id no es un UUID", async () => {
    internoService.registrarPartida.mockRejectedValue(
      new ErrorHttp(400, "usuario_id de jugador no válido"),
    );

    const res = await request(app)
      .post("/api/interno/partidas")
      .set("X-Internal-Secret", SECRETO)
      .send({
        ...body,
        jugadores: [{ usuario_id: "", posicion: 0, equipo: 0 }],
      });

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "usuario_id de jugador no válido" });
  });

  it("404 si la sala no existe", async () => {
    internoService.registrarPartida.mockRejectedValue(
      new ErrorHttp(404, "la sala no existe"),
    );

    const res = await request(app)
      .post("/api/interno/partidas")
      .set("X-Internal-Secret", SECRETO)
      .send(body);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "la sala no existe" });
  });

  it("409 si la partida de la sala ya estaba registrada (reintento)", async () => {
    internoService.registrarPartida.mockRejectedValue(
      new ErrorHttp(409, "la partida de esta sala ya está registrada"),
    );

    const res = await request(app)
      .post("/api/interno/partidas")
      .set("X-Internal-Secret", SECRETO)
      .send(body);

    expect(res.status).toBe(409);
    expect(res.body).toEqual({
      error: "la partida de esta sala ya está registrada",
    });
  });

  it("500 genérico si falla algo que no es un ErrorHttp", async () => {
    internoService.registrarPartida.mockRejectedValue(new Error("bd caída"));
    const consola = jest.spyOn(console, "error").mockImplementation(() => {});

    const res = await request(app)
      .post("/api/interno/partidas")
      .set("X-Internal-Secret", SECRETO)
      .send(body);

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: "error interno" });
    consola.mockRestore();
  });
});
