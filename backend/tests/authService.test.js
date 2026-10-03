process.env.BCRYPT_SALT_ROUNDS = "4"; // rondas bajas: los tests no necesitan el coste de producción

jest.mock("../src/models/db", () => ({ query: jest.fn() }));
jest.mock("../src/utils/mailer", () => ({ enviarCorreo: jest.fn() }));

const pool = require("../src/models/db");
const { enviarCorreo } = require("../src/utils/mailer");
const authService = require("../src/services/authService");

const HASH_VALIDO = "a".repeat(64);
const OTRO_HASH_VALIDO = "b".repeat(64);

beforeEach(() => {
  jest.clearAllMocks();
});

describe("authService.registrar", () => {
  it("guarda el email en minúsculas y un hash bcrypt, nunca el hash recibido en claro", async () => {
    pool.query.mockResolvedValueOnce({
      rows: [{ id: "u1", email: "ana@test.com", nombre_visible: "Ana" }],
    });

    const usuario = await authService.registrar({
      email: "Ana@Test.com",
      password_hash: HASH_VALIDO,
      nombre_visible: "  Ana  ",
    });

    expect(usuario).toEqual({
      id: "u1",
      email: "ana@test.com",
      nombre_visible: "Ana",
    });
    const [, params] = pool.query.mock.calls[0];
    expect(params[0]).toBe("ana@test.com");
    expect(params[1]).not.toBe(HASH_VALIDO);
    expect(params[2]).toBe("Ana");
  });

  it("rechaza un email con formato inválido", async () => {
    await expect(
      authService.registrar({
        email: "no-es-un-email",
        password_hash: HASH_VALIDO,
        nombre_visible: "Ana",
      }),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.query).not.toHaveBeenCalled();
  });

  it("rechaza un password_hash que no sea un SHA-256 en hexadecimal", async () => {
    await expect(
      authService.registrar({
        email: "ana@test.com",
        password_hash: "no-es-un-hash",
        nombre_visible: "Ana",
      }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("rechaza un nombre_visible vacío", async () => {
    await expect(
      authService.registrar({
        email: "ana@test.com",
        password_hash: HASH_VALIDO,
        nombre_visible: "   ",
      }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("traduce la violación de email único en un 409", async () => {
    pool.query.mockRejectedValueOnce({ code: "23505" });

    await expect(
      authService.registrar({
        email: "ana@test.com",
        password_hash: HASH_VALIDO,
        nombre_visible: "Ana",
      }),
    ).rejects.toMatchObject({ status: 409 });
  });
});

describe("authService.login", () => {
  it("devuelve el usuario cuando el password_hash coincide con el bcrypt guardado", async () => {
    const bcrypt = require("bcrypt");
    const hashGuardado = await bcrypt.hash(HASH_VALIDO, 4);
    pool.query.mockResolvedValueOnce({
      rows: [
        {
          id: "u1",
          email: "ana@test.com",
          nombre_visible: "Ana",
          password_hash: hashGuardado,
        },
      ],
    });

    const usuario = await authService.login({
      email: "ana@test.com",
      password_hash: HASH_VALIDO,
    });

    expect(usuario).toEqual({
      id: "u1",
      email: "ana@test.com",
      nombre_visible: "Ana",
    });
  });

  it("devuelve 401 si el usuario no existe", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    await expect(
      authService.login({
        email: "nadie@test.com",
        password_hash: HASH_VALIDO,
      }),
    ).rejects.toMatchObject({ status: 401 });
  });

  it("devuelve 401 si el password_hash no coincide", async () => {
    const bcrypt = require("bcrypt");
    const hashGuardado = await bcrypt.hash(HASH_VALIDO, 4);
    pool.query.mockResolvedValueOnce({
      rows: [
        {
          id: "u1",
          email: "ana@test.com",
          nombre_visible: "Ana",
          password_hash: hashGuardado,
        },
      ],
    });

    await expect(
      authService.login({
        email: "ana@test.com",
        password_hash: OTRO_HASH_VALIDO,
      }),
    ).rejects.toMatchObject({ status: 401 });
  });

  it("rechaza formatos inválidos antes de tocar la base de datos", async () => {
    await expect(
      authService.login({ email: "x", password_hash: HASH_VALIDO }),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.query).not.toHaveBeenCalled();
  });
});

describe("authService.solicitarRecuperacion", () => {
  it("si el correo existe, guarda un código hasheado y envía el correo", async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [{ id: "u1" }] }) // SELECT usuario
      .mockResolvedValueOnce({ rows: [] }); // INSERT codigo

    const resultado = await authService.solicitarRecuperacion({
      email: "ana@test.com",
    });

    expect(resultado).toEqual({
      mensaje: "si el correo existe, se ha enviado un código de recuperación",
    });
    expect(pool.query).toHaveBeenCalledTimes(2);
    const [, paramsInsert] = pool.query.mock.calls[1];
    expect(paramsInsert[0]).toBe("u1");
    expect(paramsInsert[1]).toMatch(/^[a-f0-9]{64}$/);
    expect(enviarCorreo).toHaveBeenCalledTimes(1);
    expect(enviarCorreo.mock.calls[0][0].to).toBe("ana@test.com");
    expect(enviarCorreo.mock.calls[0][0].text).toMatch(/\d{6}/);
  });

  it("si el correo no existe, responde igual pero no inserta código ni envía correo", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] }); // SELECT usuario

    const resultado = await authService.solicitarRecuperacion({
      email: "nadie@test.com",
    });

    expect(resultado).toEqual({
      mensaje: "si el correo existe, se ha enviado un código de recuperación",
    });
    expect(pool.query).toHaveBeenCalledTimes(1);
    expect(enviarCorreo).not.toHaveBeenCalled();
  });

  it("rechaza un email con formato inválido", async () => {
    await expect(
      authService.solicitarRecuperacion({ email: "no-valido" }),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.query).not.toHaveBeenCalled();
  });
});

describe("authService.restablecerPassword", () => {
  it("actualiza la contraseña e invalida el código cuando es válido", async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [{ id: "u1" }] }) // SELECT usuario
      .mockResolvedValueOnce({ rows: [{ id: "c1" }] }) // SELECT código válido
      .mockResolvedValueOnce({ rows: [] }) // UPDATE usuarios
      .mockResolvedValueOnce({ rows: [] }); // UPDATE codigos_recuperacion

    const resultado = await authService.restablecerPassword({
      email: "ana@test.com",
      codigo: "123456",
      password_hash: OTRO_HASH_VALIDO,
    });

    expect(resultado).toEqual({ mensaje: "contraseña actualizada" });
    expect(pool.query).toHaveBeenCalledTimes(4);
    const [, paramsUpdate] = pool.query.mock.calls[2];
    expect(paramsUpdate[0]).not.toBe(OTRO_HASH_VALIDO);
    expect(paramsUpdate[1]).toBe("u1");
  });

  it("rechaza un código con formato inválido sin tocar la base de datos", async () => {
    await expect(
      authService.restablecerPassword({
        email: "ana@test.com",
        codigo: "12",
        password_hash: HASH_VALIDO,
      }),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.query).not.toHaveBeenCalled();
  });

  it("devuelve 400 si el usuario no existe", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] }); // SELECT usuario

    await expect(
      authService.restablecerPassword({
        email: "nadie@test.com",
        codigo: "123456",
        password_hash: HASH_VALIDO,
      }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("devuelve 400 si el código no es válido, ya se usó o ha caducado", async () => {
    pool.query
      .mockResolvedValueOnce({ rows: [{ id: "u1" }] }) // SELECT usuario
      .mockResolvedValueOnce({ rows: [] }); // SELECT código: ninguno coincide

    await expect(
      authService.restablecerPassword({
        email: "ana@test.com",
        codigo: "999999",
        password_hash: HASH_VALIDO,
      }),
    ).rejects.toMatchObject({ status: 400 });
  });
});
