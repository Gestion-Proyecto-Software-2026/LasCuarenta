jest.mock("../src/services/lobbyService", () => ({
  listarSalas: jest.fn(),
  crearSala: jest.fn(),
  unirseSala: jest.fn(),
  salirSala: jest.fn(),
  expulsarJugador: jest.fn(),
  anadirMaquina: jest.fn(),
  quitarMaquina: jest.fn(),
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
    expect(lobbyService.unirseSala).toHaveBeenCalledWith(
      SALA_ID,
      "u1",
      undefined,
    );
  });

  it("pasa el password_hash del body al servicio", async () => {
    lobbyService.unirseSala.mockResolvedValue({ id: SALA_ID });

    await request(app)
      .post(`/api/salas/${SALA_ID}/unirse`)
      .set("Authorization", `Bearer ${token}`)
      .send({ password_hash: "a".repeat(64) });

    expect(lobbyService.unirseSala).toHaveBeenCalledWith(
      SALA_ID,
      "u1",
      "a".repeat(64),
    );
  });

  it("403 con contraseña incorrecta", async () => {
    lobbyService.unirseSala.mockRejectedValue(
      new ErrorHttp(403, "contraseña incorrecta"),
    );

    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/unirse`)
      .set("Authorization", `Bearer ${token}`)
      .send({ password_hash: "b".repeat(64) });

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "contraseña incorrecta" });
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

describe("DELETE /api/salas/:id/unirse", () => {
  it("204 y pasa el id del usuario autenticado al servicio", async () => {
    lobbyService.salirSala.mockResolvedValue(undefined);

    const res = await request(app)
      .delete(`/api/salas/${SALA_ID}/unirse`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(204);
    expect(lobbyService.salirSala).toHaveBeenCalledWith(SALA_ID, "u1");
  });

  it("404 si no eres participante de la sala", async () => {
    lobbyService.salirSala.mockRejectedValue(
      new ErrorHttp(404, "no formas parte de esta sala"),
    );

    const res = await request(app)
      .delete(`/api/salas/${SALA_ID}/unirse`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "no formas parte de esta sala" });
  });
});

describe("POST /api/salas/:id/expulsar", () => {
  const EXPULSADO = "33333333-3333-4333-8333-333333333333";

  it("401 sin token", async () => {
    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/expulsar`)
      .send({ usuario_id: EXPULSADO });

    expect(res.status).toBe(401);
    expect(lobbyService.expulsarJugador).not.toHaveBeenCalled();
  });

  it("200 y pasa sala, usuario autenticado y expulsado al servicio", async () => {
    const sala = { id: SALA_ID, capacidad: 2, jugadores_actuales: 1 };
    lobbyService.expulsarJugador.mockResolvedValue(sala);

    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/expulsar`)
      .set("Authorization", `Bearer ${token}`)
      .send({ usuario_id: EXPULSADO });

    expect(res.status).toBe(200);
    expect(res.body).toEqual(sala);
    expect(lobbyService.expulsarJugador).toHaveBeenCalledWith(
      SALA_ID,
      "u1",
      EXPULSADO,
    );
  });

  it("403 si el servicio rechaza porque no es el creador", async () => {
    lobbyService.expulsarJugador.mockRejectedValue(
      new ErrorHttp(403, "solo el creador de la sala puede expulsar"),
    );

    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/expulsar`)
      .set("Authorization", `Bearer ${token}`)
      .send({ usuario_id: EXPULSADO });

    expect(res.status).toBe(403);
    expect(res.body).toEqual({
      error: "solo el creador de la sala puede expulsar",
    });
  });
});

describe("POST /api/salas/:id/maquinas (PBI-20)", () => {
  it("401 sin token", async () => {
    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/maquinas`)
      .send({ dificultad: "normal" });

    expect(res.status).toBe(401);
    expect(lobbyService.anadirMaquina).not.toHaveBeenCalled();
  });

  it("201 y pasa sala, usuario autenticado y datos al servicio", async () => {
    const sala = {
      id: SALA_ID,
      capacidad: 4,
      jugadores_actuales: 2,
      maquinas: [{ posicion: 1, dificultad: "dificil" }],
    };
    lobbyService.anadirMaquina.mockResolvedValue(sala);

    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/maquinas`)
      .set("Authorization", `Bearer ${token}`)
      .send({ dificultad: "dificil", posicion: 1 });

    expect(res.status).toBe(201);
    expect(res.body).toEqual(sala);
    expect(lobbyService.anadirMaquina).toHaveBeenCalledWith(SALA_ID, "u1", {
      dificultad: "dificil",
      posicion: 1,
    });
  });

  it("403 si el servicio rechaza porque no es el creador", async () => {
    lobbyService.anadirMaquina.mockRejectedValue(
      new ErrorHttp(403, "solo el creador"),
    );

    const res = await request(app)
      .post(`/api/salas/${SALA_ID}/maquinas`)
      .set("Authorization", `Bearer ${token}`)
      .send({});

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "solo el creador" });
  });
});

describe("DELETE /api/salas/:id/maquinas/:posicion (PBI-20)", () => {
  it("401 sin token", async () => {
    const res = await request(app).delete(`/api/salas/${SALA_ID}/maquinas/1`);

    expect(res.status).toBe(401);
    expect(lobbyService.quitarMaquina).not.toHaveBeenCalled();
  });

  it("200 y pasa la posición como número", async () => {
    const sala = {
      id: SALA_ID,
      capacidad: 4,
      jugadores_actuales: 1,
      maquinas: [],
    };
    lobbyService.quitarMaquina.mockResolvedValue(sala);

    const res = await request(app)
      .delete(`/api/salas/${SALA_ID}/maquinas/1`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual(sala);
    expect(lobbyService.quitarMaquina).toHaveBeenCalledWith(SALA_ID, "u1", 1);
  });

  it("404 si el servicio dice que no hay máquina", async () => {
    lobbyService.quitarMaquina.mockRejectedValue(
      new ErrorHttp(404, "no hay ninguna máquina en esa plaza"),
    );

    const res = await request(app)
      .delete(`/api/salas/${SALA_ID}/maquinas/3`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(404);
  });
});
