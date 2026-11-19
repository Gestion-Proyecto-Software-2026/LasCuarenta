jest.mock("../src/services/historialService", () => ({
  listarHistorial: jest.fn(),
  obtenerEstadisticas: jest.fn(),
  obtenerPrivacidad: jest.fn(),
  cambiarPrivacidad: jest.fn(),
}));

const request = require("supertest");
const jwt = require("jsonwebtoken");
const app = require("../src/app");
const historialService = require("../src/services/historialService");
const { ErrorHttp } = require("../src/utils/errorHttp");

const YO = "22222222-2222-4222-8222-222222222222";
const OTRO = "33333333-3333-4333-8333-333333333333";
let token;

beforeAll(() => {
  process.env.JWT_SECRET = "secreto_de_test";
  token = jwt.sign({ id: YO }, process.env.JWT_SECRET);
});

beforeEach(() => {
  jest.clearAllMocks();
});

describe("autenticación de las rutas de historial", () => {
  it.each([
    ["get", "/api/usuarios/me/historial"],
    ["get", `/api/usuarios/${OTRO}/historial`],
    ["get", "/api/usuarios/me/estadisticas"],
    ["get", "/api/usuarios/me/privacidad"],
    ["put", "/api/usuarios/me/privacidad"],
  ])("401 sin token en %s %s", async (metodo, ruta) => {
    const res = await request(app)[metodo](ruta);

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "no autenticado" });
    for (const funcion of Object.values(historialService)) {
      expect(funcion).not.toHaveBeenCalled();
    }
  });

  it("401 con un token inválido", async () => {
    const res = await request(app)
      .get("/api/usuarios/me/historial")
      .set("Authorization", "Bearer token_falso");

    expect(res.status).toBe(401);
    expect(historialService.listarHistorial).not.toHaveBeenCalled();
  });
});

describe("GET /api/usuarios/:id/historial", () => {
  it("200 con las partidas y pasa `me`, el usuario del token y la query al servicio", async () => {
    const partidas = [{ partida_id: "p1", resultado: "victoria" }];
    historialService.listarHistorial.mockResolvedValue(partidas);

    const res = await request(app)
      .get("/api/usuarios/me/historial?juego=mus&limite=20")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual(partidas);
    expect(historialService.listarHistorial).toHaveBeenCalledWith("me", YO, {
      juego: "mus",
      limite: "20",
    });
  });

  it("200 con el historial de otro usuario por su id", async () => {
    historialService.listarHistorial.mockResolvedValue([]);

    const res = await request(app)
      .get(`/api/usuarios/${OTRO}/historial`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
    expect(historialService.listarHistorial).toHaveBeenCalledWith(OTRO, YO, {});
  });

  it("400 si el servicio rechaza el id, el juego o el límite", async () => {
    historialService.listarHistorial.mockRejectedValue(
      new ErrorHttp(400, "limite no válido (entero de 1 a 500)"),
    );

    const res = await request(app)
      .get("/api/usuarios/me/historial?limite=0")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "limite no válido (entero de 1 a 500)" });
  });

  it("403 si el historial es privado", async () => {
    historialService.listarHistorial.mockRejectedValue(
      new ErrorHttp(403, "este historial es privado"),
    );

    const res = await request(app)
      .get(`/api/usuarios/${OTRO}/historial`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "este historial es privado" });
  });

  it("404 si el usuario no existe", async () => {
    historialService.listarHistorial.mockRejectedValue(
      new ErrorHttp(404, "el usuario no existe"),
    );

    const res = await request(app)
      .get(`/api/usuarios/${OTRO}/historial`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "el usuario no existe" });
  });

  it("500 genérico si falla algo que no es un ErrorHttp", async () => {
    historialService.listarHistorial.mockRejectedValue(new Error("bd caída"));
    const consola = jest.spyOn(console, "error").mockImplementation(() => {});

    const res = await request(app)
      .get("/api/usuarios/me/historial")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: "error interno" });
    consola.mockRestore();
  });
});

describe("GET /api/usuarios/:id/estadisticas", () => {
  it("200 con las estadísticas del usuario pedido", async () => {
    const estadisticas = {
      usuario_id: YO,
      totales: { jugadas: 1, victorias: 1, derrotas: 0 },
    };
    historialService.obtenerEstadisticas.mockResolvedValue(estadisticas);

    const res = await request(app)
      .get("/api/usuarios/me/estadisticas")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual(estadisticas);
    expect(historialService.obtenerEstadisticas).toHaveBeenCalledWith("me", YO);
  });

  it("400 si el id no es válido", async () => {
    historialService.obtenerEstadisticas.mockRejectedValue(
      new ErrorHttp(400, "id de usuario no válido"),
    );

    const res = await request(app)
      .get("/api/usuarios/nadie/estadisticas")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(400);
    expect(historialService.obtenerEstadisticas).toHaveBeenCalledWith(
      "nadie",
      YO,
    );
  });

  it("403 si el historial es privado", async () => {
    historialService.obtenerEstadisticas.mockRejectedValue(
      new ErrorHttp(403, "este historial es privado"),
    );

    const res = await request(app)
      .get(`/api/usuarios/${OTRO}/estadisticas`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "este historial es privado" });
  });

  it("404 si el usuario no existe", async () => {
    historialService.obtenerEstadisticas.mockRejectedValue(
      new ErrorHttp(404, "el usuario no existe"),
    );

    const res = await request(app)
      .get(`/api/usuarios/${OTRO}/estadisticas`)
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(404);
  });
});

describe("/api/usuarios/me/privacidad", () => {
  it("GET 200 con la privacidad del usuario del token", async () => {
    historialService.obtenerPrivacidad.mockResolvedValue({
      historial_publico: true,
    });

    const res = await request(app)
      .get("/api/usuarios/me/privacidad")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ historial_publico: true });
    expect(historialService.obtenerPrivacidad).toHaveBeenCalledWith(YO);
  });

  it("GET 404 si el usuario del token ya no existe", async () => {
    historialService.obtenerPrivacidad.mockRejectedValue(
      new ErrorHttp(404, "el usuario no existe"),
    );

    const res = await request(app)
      .get("/api/usuarios/me/privacidad")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(404);
  });

  it("PUT 200 pasa el body y el usuario del token al servicio", async () => {
    historialService.cambiarPrivacidad.mockResolvedValue({
      historial_publico: false,
    });

    const res = await request(app)
      .put("/api/usuarios/me/privacidad")
      .set("Authorization", `Bearer ${token}`)
      .send({ historial_publico: false });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ historial_publico: false });
    expect(historialService.cambiarPrivacidad).toHaveBeenCalledWith(YO, {
      historial_publico: false,
    });
  });

  it("PUT sin body pasa un objeto vacío al servicio", async () => {
    historialService.cambiarPrivacidad.mockRejectedValue(
      new ErrorHttp(400, "historial_publico tiene que ser true o false"),
    );

    const res = await request(app)
      .put("/api/usuarios/me/privacidad")
      .set("Authorization", `Bearer ${token}`);

    expect(res.status).toBe(400);
    expect(historialService.cambiarPrivacidad).toHaveBeenCalledWith(YO, {});
  });

  it("PUT 400 si historial_publico no es booleano", async () => {
    historialService.cambiarPrivacidad.mockRejectedValue(
      new ErrorHttp(400, "historial_publico tiene que ser true o false"),
    );

    const res = await request(app)
      .put("/api/usuarios/me/privacidad")
      .set("Authorization", `Bearer ${token}`)
      .send({ historial_publico: "sí" });

    expect(res.status).toBe(400);
    expect(res.body).toEqual({
      error: "historial_publico tiene que ser true o false",
    });
  });
});
