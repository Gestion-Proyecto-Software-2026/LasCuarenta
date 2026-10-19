jest.mock("../src/services/lobbyService", () => ({
  listarSalas: jest.fn(),
  crearSala: jest.fn(),
  unirseSala: jest.fn(),
}));

const request = require("supertest");
const jwt = require("jsonwebtoken");
const app = require("../src/app");
const lobbyService = require("../src/services/lobbyService");
const { ErrorHttp } = require("../src/utils/errorHttp");

const SALA_ID = "11111111-1111-4111-8111-111111111111";
let token;

beforeAll(() => {
  process.env.JWT_SECRET = "secreto_de_test";
  token = jwt.sign({ id: "u1" }, process.env.JWT_SECRET);
});

beforeEach(() => {
  jest.clearAllMocks();
});

describe("autenticación de las rutas de lobby", () => {
  it("401 sin token en cualquier ruta de salas", async () => {
    const res = await request(app).get("/api/salas");

    expect(res.status).toBe(401);
    expect(lobbyService.listarSalas).not.toHaveBeenCalled();
  });

  it("401 con un token inválido", async () => {
    const res = await request(app)
      .get("/api/salas")
      .set("Authorization", "Bearer token_falso");

    expect(res.status).toBe(401);
  });
});

describe("GET /api/salas", () => {
  it("200 con la lista de salas del servicio", async () => {
    const salas = [{ id: SALA_ID, juego: "guinote", jugadores_actuales: 1 }];
    lobbyService.listarSalas.mockResolvedValue(salas);

    const res = await request(app)
      .get("/api/salas?juego=guinote")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual(salas);
    expect(lobbyService.listarSalas).toHaveBeenCalledWith({ juego: "guinote" });
  });

  it("400 si el servicio rechaza el juego", async () => {
    lobbyService.listarSalas.mockRejectedValue(
      new ErrorHttp(400, "juego no válido"),
    );

    const res = await request(app)
      .get("/api/salas?juego=poker")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "juego no válido" });
  });
});

describe("POST /api/salas", () => {
  it("201 y pasa el id del usuario autenticado al servicio", async () => {
    const sala = {
      id: SALA_ID,
      juego: "guinote",
      estado: "esperando",
      capacidad: 4,
    };
    lobbyService.crearSala.mockResolvedValue(sala);

    const res = await request(app)
      .post("/api/salas")
      .set("Authorization", `Bearer ${token}`)
      .send({ juego: "guinote" });

    expect(res.status).toBe(201);
    expect(res.body).toEqual(sala);
    expect(lobbyService.crearSala).toHaveBeenCalledWith(
      { juego: "guinote" },
      "u1",
    );
  });
});

describe("POST /api/salas/:id/unirse", () => {
  it("200 con la sala actualizada", async () => {
    lobbyService.unirseSala.mockResolvedValue({
      id: SALA_ID,
      jugadores_actuales: 2,
    });

    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/unirse`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.jugadores_actuales).toBe(2);
    expect(lobbyService.unirseSala).toHaveBeenCalledWith(SALA_ID, "u1");
  });

  it("409 cuando la sala está llena", async () => {
    lobbyService.unirseSala.mockRejectedValue(
      new ErrorHttp(409, "la sala está llena"),
    );

    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/unirse`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: "la sala está llena" });
  });
});

describe("POST /api/salas/:id/expulsar", () => {
  it("sigue en 501 hasta PBI-09", async () => {
    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/expulsar`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(501);
  });
});
