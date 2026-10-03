jest.mock("../src/services/authService", () => {
  const actual = jest.requireActual("../src/services/authService");
  return {
    AuthError: actual.AuthError,
    registrar: jest.fn(),
    login: jest.fn(),
    solicitarRecuperacion: jest.fn(),
    restablecerPassword: jest.fn(),
  };
});

const request = require("supertest");
const jwt = require("jsonwebtoken");
const app = require("../src/app");
const authService = require("../src/services/authService");

beforeAll(() => {
  process.env.JWT_SECRET = "secreto_de_test";
});

beforeEach(() => {
  jest.clearAllMocks();
});

describe("POST /api/auth/registro", () => {
  it("201 con el usuario creado por el servicio", async () => {
    authService.registrar.mockResolvedValue({
      id: "u1",
      email: "ana@test.com",
      nombre_visible: "Ana",
    });

    const res = await request(app)
      .post("/api/auth/registro")
      .send({
        email: "ana@test.com",
        password_hash: "a".repeat(64),
        nombre_visible: "Ana",
      });

    expect(res.status).toBe(201);
    expect(res.body).toEqual({
      id: "u1",
      email: "ana@test.com",
      nombre_visible: "Ana",
    });
  });

  it("propaga el status de un AuthError (p. ej. 409 por correo duplicado)", async () => {
    authService.registrar.mockRejectedValue(
      new authService.AuthError(409, "el correo ya está registrado"),
    );

    const res = await request(app).post("/api/auth/registro").send({});

    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: "el correo ya está registrado" });
  });
});

describe("POST /api/auth/login", () => {
  it("200 con un JWT firmado y los datos del usuario", async () => {
    authService.login.mockResolvedValue({
      id: "u1",
      email: "ana@test.com",
      nombre_visible: "Ana",
    });

    const res = await request(app)
      .post("/api/auth/login")
      .send({ email: "ana@test.com", password_hash: "a".repeat(64) });

    expect(res.status).toBe(200);
    expect(res.body.usuario).toEqual({
      id: "u1",
      email: "ana@test.com",
      nombre_visible: "Ana",
    });
    const payload = jwt.verify(res.body.token, process.env.JWT_SECRET);
    expect(payload.id).toBe("u1");
  });

  it("401 cuando el servicio rechaza las credenciales", async () => {
    authService.login.mockRejectedValue(
      new authService.AuthError(401, "credenciales inválidas"),
    );

    const res = await request(app).post("/api/auth/login").send({});

    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "credenciales inválidas" });
  });
});

describe("POST /api/auth/recuperar", () => {
  it("200 con el mensaje genérico del servicio", async () => {
    authService.solicitarRecuperacion.mockResolvedValue({
      mensaje: "si el correo existe, se ha enviado un código de recuperación",
    });

    const res = await request(app)
      .post("/api/auth/recuperar")
      .send({ email: "ana@test.com" });

    expect(res.status).toBe(200);
    expect(res.body.mensaje).toMatch(/código de recuperación/);
  });

  it("400 cuando el servicio rechaza el formato del email", async () => {
    authService.solicitarRecuperacion.mockRejectedValue(
      new authService.AuthError(400, "email inválido"),
    );

    const res = await request(app)
      .post("/api/auth/recuperar")
      .send({ email: "no-valido" });

    expect(res.status).toBe(400);
  });
});

describe("POST /api/auth/restablecer", () => {
  it("200 cuando el servicio confirma el cambio de contraseña", async () => {
    authService.restablecerPassword.mockResolvedValue({
      mensaje: "contraseña actualizada",
    });

    const res = await request(app)
      .post("/api/auth/restablecer")
      .send({
        email: "ana@test.com",
        codigo: "123456",
        password_hash: "a".repeat(64),
      });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ mensaje: "contraseña actualizada" });
  });

  it("400 cuando el código es inválido o ha caducado", async () => {
    authService.restablecerPassword.mockRejectedValue(
      new authService.AuthError(400, "código inválido o caducado"),
    );

    const res = await request(app).post("/api/auth/restablecer").send({});

    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "código inválido o caducado" });
  });
});
