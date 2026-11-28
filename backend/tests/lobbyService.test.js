jest.mock("../src/models/db", () => ({ query: jest.fn(), connect: jest.fn() }));

const pool = require("../src/models/db");
const lobbyService = require("../src/services/lobbyService");

const SALA_ID = "11111111-1111-4111-8111-111111111111";
const USUARIO_ID = "22222222-2222-4222-8222-222222222222";
const OTRO_ID = "33333333-3333-4333-8333-333333333333";

let cliente;

// Enruta las consultas del cliente transaccional según el SQL, sin depender del orden.
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

function sqlsEjecutados() {
  return cliente.query.mock.calls.map(([sql]) => sql.trim());
}

beforeEach(() => {
  jest.clearAllMocks();
  process.env.GAME_SERVER_ADDRESS = "localhost:9000";
});

describe("lobbyService.listarSalas", () => {
  it("devuelve las salas en espera sin filtrar cuando no se pasa juego", async () => {
    const salas = [{ id: SALA_ID, juego: "guinote", jugadores_actuales: 2 }];
    pool.query.mockResolvedValueOnce({ rows: salas });

    const resultado = await lobbyService.listarSalas({});

    expect(resultado).toEqual(salas);
    const [sql, params] = pool.query.mock.calls[0];
    expect(sql).toContain("estado = 'esperando'");
    expect(params).toEqual([null]);
  });

  it("filtra por juego cuando se indica", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    await lobbyService.listarSalas({ juego: "guinote" });

    expect(pool.query.mock.calls[0][1]).toEqual(["guinote"]);
  });

  it("rechaza un juego desconocido sin consultar la base de datos", async () => {
    await expect(
      lobbyService.listarSalas({ juego: "poker" }),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.query).not.toHaveBeenCalled();
  });

  it("agrega los jugadores (con nombre_visible) de cada sala en la misma consulta", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    await lobbyService.listarSalas({});

    const [sql] = pool.query.mock.calls[0];
    expect(sql).toContain("json_agg");
    expect(sql).toContain("LEFT JOIN usuarios");
  });
});

describe("lobbyService.crearSala", () => {
  it("crea la sala de 4 plazas y sienta al creador en la posición 0, en una transacción", async () => {
    prepararCliente({
      "INSERT INTO salas": [
        { id: SALA_ID, juego: "guinote", estado: "esperando", capacidad: 4 },
      ],
    });

    const sala = await lobbyService.crearSala({ juego: "guinote" }, USUARIO_ID);

    expect(sala).toEqual({
      id: SALA_ID,
      juego: "guinote",
      estado: "esperando",
      capacidad: 4,
      tiene_contrasena: false,
      servidor_direccion: "localhost:9000",
    });
    expect(sqlsEjecutados()).toEqual([
      "BEGIN",
      expect.stringContaining("INSERT INTO salas"),
      expect.stringContaining("INSERT INTO sala_participantes"),
      "COMMIT",
    ]);
    const insertSala = cliente.query.mock.calls[1];
    expect(insertSala[1]).toEqual([
      "guinote",
      4,
      USUARIO_ID,
      "Sala de Guiñote",
      null,
    ]);
    const insertParticipante = cliente.query.mock.calls[2];
    expect(insertParticipante[1]).toEqual([SALA_ID, USUARIO_ID]);
    expect(cliente.release).toHaveBeenCalledTimes(1);
  });

  it("crea una sala de Mus a 2 jugadores con nombre y contraseña", async () => {
    prepararCliente({
      "INSERT INTO salas": [
        {
          id: SALA_ID,
          juego: "mus",
          estado: "esperando",
          capacidad: 2,
          nombre: "Partida rápida",
        },
      ],
    });

    const sala = await lobbyService.crearSala(
      {
        juego: "mus",
        capacidad: 2,
        nombre: "Partida rápida",
        password_hash: "a".repeat(64),
      },
      USUARIO_ID,
    );

    expect(sala).toEqual({
      id: SALA_ID,
      juego: "mus",
      estado: "esperando",
      capacidad: 2,
      nombre: "Partida rápida",
      tiene_contrasena: true,
      servidor_direccion: "localhost:9000",
    });
    const insertSala = cliente.query.mock.calls[1];
    expect(insertSala[1][0]).toBe("mus");
    expect(insertSala[1][1]).toBe(2);
    expect(insertSala[1][3]).toBe("Partida rápida");
    expect(insertSala[1][4]).not.toBeNull();
    // Se guarda el bcrypt del hash, nunca el hash tal cual.
    expect(insertSala[1][4]).not.toBe("a".repeat(64));
  });

  it("rechaza juegos que no existen, sin abrir transacción", async () => {
    await expect(
      lobbyService.crearSala({ juego: "parchis" }, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("crea una sala de Tute a 2 o a 4 jugadores", async () => {
    for (const capacidad of [2, 4]) {
      prepararCliente({
        "INSERT INTO salas": [
          {
            id: SALA_ID,
            juego: "tute",
            estado: "esperando",
            capacidad,
            nombre: "Sala de Tute",
          },
        ],
      });
      const sala = await lobbyService.crearSala(
        { juego: "tute", capacidad, nombre: "Sala de Tute" },
        USUARIO_ID,
      );
      expect(sala.juego).toBe("tute");
      expect(sala.capacidad).toBe(capacidad);
      const insertSala = cliente.query.mock.calls[1];
      expect(insertSala[1][0]).toBe("tute");
      expect(insertSala[1][1]).toBe(capacidad);
    }
  });

  it("rechaza una capacidad no admitida para el juego, sin abrir transacción", async () => {
    await expect(
      lobbyService.crearSala({ juego: "guinote", capacidad: 3 }, USUARIO_ID),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("rechaza un nombre de sala vacío o demasiado largo", async () => {
    await expect(
      lobbyService.crearSala({ juego: "guinote", nombre: "" }, USUARIO_ID),
    ).rejects.toMatchObject({ status: 400 });
    await expect(
      lobbyService.crearSala(
        { juego: "guinote", nombre: "x".repeat(41) },
        USUARIO_ID,
      ),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("rechaza un password_hash que no sea un SHA-256 hexadecimal", async () => {
    await expect(
      lobbyService.crearSala(
        { juego: "guinote", password_hash: "no-es-un-hash" },
        USUARIO_ID,
      ),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("hace ROLLBACK y libera el cliente si falla un insert", async () => {
    prepararCliente({
      "INSERT INTO sala_participantes": new Error("fallo de BD"),
      "INSERT INTO salas": [
        { id: SALA_ID, juego: "guinote", estado: "esperando", capacidad: 4 },
      ],
    });

    await expect(
      lobbyService.crearSala({ juego: "guinote" }, USUARIO_ID),
    ).rejects.toThrow("fallo de BD");
    expect(sqlsEjecutados()).toContain("ROLLBACK");
    expect(sqlsEjecutados()).not.toContain("COMMIT");
    expect(cliente.release).toHaveBeenCalledTimes(1);
  });
});

describe("lobbyService.unirseSala", () => {
  const salaEsperando = {
    id: SALA_ID,
    juego: "guinote",
    estado: "esperando",
    capacidad: 4,
    creador_id: OTRO_ID,
  };

  it("asigna la primera posición libre y devuelve la sala con el recuento actualizado", async () => {
    prepararCliente({
      "FROM salas WHERE id": [salaEsperando],
      "FROM sala_participantes WHERE sala_id": [
        { usuario_id: OTRO_ID, posicion: 0 },
        { usuario_id: "44444444-4444-4444-8444-444444444444", posicion: 2 },
      ],
    });

    const sala = await lobbyService.unirseSala(SALA_ID, USUARIO_ID);

    expect(sala).toEqual({
      id: SALA_ID,
      juego: "guinote",
      estado: "esperando",
      capacidad: 4,
      creador_id: OTRO_ID,
      jugadores_actuales: 3,
      servidor_direccion: "localhost:9000",
    });
    const insert = cliente.query.mock.calls.find(([sql]) =>
      sql.includes("INSERT INTO sala_participantes"),
    );
    expect(insert[1]).toEqual([SALA_ID, USUARIO_ID, 1]);
    expect(sqlsEjecutados()).toContain("COMMIT");
  });

  it("bloquea la fila de la sala con FOR UPDATE", async () => {
    prepararCliente({ "FROM salas WHERE id": [salaEsperando] });

    await lobbyService.unirseSala(SALA_ID, USUARIO_ID).catch(() => {});

    expect(
      sqlsEjecutados().find((sql) => sql.includes("FROM salas")),
    ).toContain("FOR UPDATE");
  });

  it("rechaza un id que no es UUID sin tocar la base de datos", async () => {
    await expect(
      lobbyService.unirseSala("no-es-uuid", USUARIO_ID),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("404 si la sala no existe", async () => {
    prepararCliente({ "FROM salas WHERE id": [] });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 404,
    });
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("409 si la sala ya no está en espera", async () => {
    prepararCliente({
      "FROM salas WHERE id": [{ ...salaEsperando, estado: "en_curso" }],
    });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 409,
    });
  });

  it("409 si el usuario ya está sentado en la sala", async () => {
    prepararCliente({
      "FROM salas WHERE id": [salaEsperando],
      "FROM sala_participantes WHERE sala_id": [
        { usuario_id: USUARIO_ID, posicion: 0 },
      ],
    });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 409,
      message: "ya estás en esta sala",
    });
  });

  it("409 si no quedan plazas libres", async () => {
    prepararCliente({
      "FROM salas WHERE id": [salaEsperando],
      "FROM sala_participantes WHERE sala_id": [
        { usuario_id: "a", posicion: 0 },
        { usuario_id: "b", posicion: 1 },
        { usuario_id: "c", posicion: 2 },
        { usuario_id: "d", posicion: 3 },
      ],
    });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 409,
      message: "la sala está llena",
    });
    expect(
      sqlsEjecutados().some((sql) =>
        sql.includes("INSERT INTO sala_participantes"),
      ),
    ).toBe(false);
  });

  it("403 si la sala tiene contraseña y no coincide (o no se manda)", async () => {
    const bcrypt = require("bcrypt");
    const hashAlmacenado = await bcrypt.hash("b".repeat(64), 4);
    prepararCliente({
      "FROM salas WHERE id": [
        { ...salaEsperando, password_hash: hashAlmacenado },
      ],
    });

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID, "c".repeat(64)),
    ).rejects.toMatchObject({ status: 403, message: "contraseña incorrecta" });
    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({ status: 403 });
    expect(
      sqlsEjecutados().some((sql) =>
        sql.includes("INSERT INTO sala_participantes"),
      ),
    ).toBe(false);
  });

  it("deja unirse si la contraseña coincide", async () => {
    const bcrypt = require("bcrypt");
    const hashAlmacenado = await bcrypt.hash("b".repeat(64), 4);
    prepararCliente({
      "FROM salas WHERE id": [
        { ...salaEsperando, password_hash: hashAlmacenado },
      ],
      "FROM sala_participantes WHERE sala_id": [],
    });

    const sala = await lobbyService.unirseSala(
      SALA_ID,
      USUARIO_ID,
      "b".repeat(64),
    );

    expect(sala.jugadores_actuales).toBe(1);
  });
});

describe("lobbyService.salirSala", () => {
  const salaEsperando = { id: SALA_ID, estado: "esperando" };

  it("borra al usuario de la sala y la deja viva si quedan más participantes", async () => {
    prepararCliente({
      "FROM salas WHERE id": [salaEsperando],
      "DELETE FROM sala_participantes": [],
      "COUNT(*)::int AS total": [{ total: 1 }],
    });
    cliente.query.mockImplementation(async (sql) => {
      if (sql.includes("DELETE FROM sala_participantes")) {
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes("FROM salas WHERE id")) return { rows: [salaEsperando] };
      if (sql.includes("COUNT(*)::int AS total"))
        return { rows: [{ total: 1 }] };
      return { rows: [] };
    });

    await lobbyService.salirSala(SALA_ID, USUARIO_ID);

    expect(sqlsEjecutados()).toEqual([
      "BEGIN",
      expect.stringContaining("FROM salas WHERE id"),
      expect.stringContaining("DELETE FROM sala_participantes"),
      expect.stringContaining("COUNT(*)::int AS total"),
      "COMMIT",
    ]);
    expect(
      sqlsEjecutados().some((sql) =>
        sql.includes("DELETE FROM salas WHERE id"),
      ),
    ).toBe(false);
  });

  it("borra también la sala si no queda nadie dentro", async () => {
    cliente = {
      query: jest.fn(async (sql) => {
        if (sql.includes("FROM salas WHERE id"))
          return { rows: [salaEsperando] };
        if (sql.includes("DELETE FROM sala_participantes")) {
          return { rows: [], rowCount: 1 };
        }
        if (sql.includes("COUNT(*)::int AS total"))
          return { rows: [{ total: 0 }] };
        return { rows: [] };
      }),
      release: jest.fn(),
    };
    pool.connect.mockResolvedValue(cliente);

    await lobbyService.salirSala(SALA_ID, USUARIO_ID);

    expect(
      sqlsEjecutados().some((sql) =>
        sql.includes("DELETE FROM salas WHERE id"),
      ),
    ).toBe(true);
    expect(sqlsEjecutados()).toContain("COMMIT");
  });

  it("rechaza un id que no es UUID sin tocar la base de datos", async () => {
    await expect(
      lobbyService.salirSala("no-es-uuid", USUARIO_ID),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("404 si la sala no existe", async () => {
    prepararCliente({ "FROM salas WHERE id": [] });

    await expect(
      lobbyService.salirSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({ status: 404 });
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("409 si la sala ya no está en espera", async () => {
    prepararCliente({
      "FROM salas WHERE id": [{ ...salaEsperando, estado: "en_curso" }],
    });

    await expect(
      lobbyService.salirSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({ status: 409 });
  });

  it("404 si el usuario no es participante de la sala", async () => {
    cliente = {
      query: jest.fn(async (sql) => {
        if (sql.includes("FROM salas WHERE id"))
          return { rows: [salaEsperando] };
        if (sql.includes("DELETE FROM sala_participantes")) {
          return { rows: [], rowCount: 0 };
        }
        return { rows: [] };
      }),
      release: jest.fn(),
    };
    pool.connect.mockResolvedValue(cliente);

    await expect(
      lobbyService.salirSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({
      status: 404,
      message: "no formas parte de esta sala",
    });
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });
});

describe("lobbyService.salirSala cuando sale el creador", () => {
  it("pasa la sala al siguiente jugador sentado", async () => {
    cliente = {
      query: jest.fn(async (sql) => {
        if (sql.includes("FROM salas WHERE id"))
          return {
            rows: [
              { id: SALA_ID, estado: "esperando", creador_id: USUARIO_ID },
            ],
          };
        if (sql.includes("DELETE FROM sala_participantes"))
          return { rows: [], rowCount: 1 };
        if (sql.includes("COUNT(*)::int AS total"))
          return { rows: [{ total: 1 }] };
        return { rows: [] };
      }),
      release: jest.fn(),
    };
    pool.connect.mockResolvedValue(cliente);

    await lobbyService.salirSala(SALA_ID, USUARIO_ID);

    expect(
      sqlsEjecutados().some((sql) =>
        sql.includes("UPDATE salas SET creador_id"),
      ),
    ).toBe(true);
    expect(sqlsEjecutados()).toContain("COMMIT");
  });
});

describe("lobbyService.expulsarJugador", () => {
  const salaEsperando = {
    id: SALA_ID,
    estado: "esperando",
    capacidad: 2,
    creador_id: USUARIO_ID,
  };

  function prepararExpulsion({ sala = salaEsperando, borrados = 1 } = {}) {
    cliente = {
      query: jest.fn(async (sql) => {
        if (sql.includes("FROM salas WHERE id"))
          return { rows: sala ? [sala] : [] };
        if (sql.includes("DELETE FROM sala_participantes"))
          return { rows: [], rowCount: borrados };
        if (sql.includes("COUNT(*)::int AS total"))
          return { rows: [{ total: 1 }] };
        return { rows: [] };
      }),
      release: jest.fn(),
    };
    pool.connect.mockResolvedValue(cliente);
  }

  it("saca al jugador y deja su plaza libre", async () => {
    prepararExpulsion();

    const resultado = await lobbyService.expulsarJugador(
      SALA_ID,
      USUARIO_ID,
      OTRO_ID,
    );

    expect(resultado).toEqual({
      id: SALA_ID,
      capacidad: 2,
      jugadores_actuales: 1,
    });
    const borrado = cliente.query.mock.calls.find(([sql]) =>
      sql.includes("DELETE FROM sala_participantes"),
    );
    expect(borrado[1]).toEqual([SALA_ID, OTRO_ID]);
    expect(sqlsEjecutados()).toContain("COMMIT");
  });

  it("403 si quien expulsa no es el creador", async () => {
    prepararExpulsion({ sala: { ...salaEsperando, creador_id: OTRO_ID } });

    await expect(
      lobbyService.expulsarJugador(SALA_ID, USUARIO_ID, OTRO_ID),
    ).rejects.toMatchObject({ status: 403 });
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("409 si la partida ya ha empezado", async () => {
    prepararExpulsion({ sala: { ...salaEsperando, estado: "en_curso" } });

    await expect(
      lobbyService.expulsarJugador(SALA_ID, USUARIO_ID, OTRO_ID),
    ).rejects.toMatchObject({ status: 409 });
  });

  it("404 si la sala no existe", async () => {
    prepararExpulsion({ sala: null });

    await expect(
      lobbyService.expulsarJugador(SALA_ID, USUARIO_ID, OTRO_ID),
    ).rejects.toMatchObject({ status: 404 });
  });

  it("404 si el jugador no está en la sala", async () => {
    prepararExpulsion({ borrados: 0 });

    await expect(
      lobbyService.expulsarJugador(SALA_ID, USUARIO_ID, OTRO_ID),
    ).rejects.toMatchObject({ status: 404 });
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("400 si el creador intenta expulsarse a sí mismo", async () => {
    await expect(
      lobbyService.expulsarJugador(SALA_ID, USUARIO_ID, USUARIO_ID),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it.each([
    ["no-es-uuid", OTRO_ID],
    [SALA_ID, undefined],
    [SALA_ID, "no-es-uuid"],
  ])("400 con sala %s y usuario %s", async (sala, usuario) => {
    await expect(
      lobbyService.expulsarJugador(sala, USUARIO_ID, usuario),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });
});

describe("lobbyService.anadirMaquina y quitarMaquina (PBI-20)", () => {
  const salaEsperando = {
    id: SALA_ID,
    estado: "esperando",
    capacidad: 4,
    creador_id: USUARIO_ID,
  };

  // personas y maquinas son las posiciones que ya están ocupadas.
  function prepararMaquinas({
    sala = salaEsperando,
    personas = [0],
    maquinas = [],
    borradas = 1,
  } = {}) {
    cliente = {
      query: jest.fn(async (sql) => {
        if (sql.includes("FROM salas WHERE id"))
          return { rows: sala ? [sala] : [] };
        if (sql.includes("SELECT posicion FROM sala_participantes"))
          return { rows: personas.map((posicion) => ({ posicion })) };
        if (sql.includes("SELECT posicion FROM sala_maquinas"))
          return { rows: maquinas.map((posicion) => ({ posicion })) };
        if (sql.includes("SELECT posicion, dificultad FROM sala_maquinas"))
          return {
            rows: maquinas.map((posicion) => ({
              posicion,
              dificultad: "normal",
            })),
          };
        if (sql.includes("COUNT(*)::int AS total"))
          return { rows: [{ total: personas.length }] };
        if (sql.includes("DELETE FROM sala_maquinas"))
          return { rows: [], rowCount: borradas };
        return { rows: [] };
      }),
      release: jest.fn(),
    };
    pool.connect.mockResolvedValue(cliente);
  }

  function insercion() {
    return cliente.query.mock.calls.find(([sql]) =>
      sql.includes("INSERT INTO sala_maquinas"),
    );
  }

  it("sienta la máquina en la primera plaza libre con dificultad normal", async () => {
    prepararMaquinas({ personas: [0, 1], maquinas: [] });

    const resultado = await lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, {});

    expect(insercion()[1]).toEqual([SALA_ID, 2, "normal"]);
    expect(resultado.id).toBe(SALA_ID);
    expect(resultado.capacidad).toBe(4);
    expect(sqlsEjecutados()).toContain("COMMIT");
  });

  it("respeta la dificultad y la plaza pedidas", async () => {
    prepararMaquinas();

    await lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, {
      dificultad: "dificil",
      posicion: 2,
    });

    expect(insercion()[1]).toEqual([SALA_ID, 2, "dificil"]);
  });

  it("las máquinas también ocupan plaza al buscar la primera libre", async () => {
    prepararMaquinas({ personas: [0], maquinas: [1, 2] });

    await lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, {});

    expect(insercion()[1][1]).toBe(3);
  });

  it("409 si la sala está llena", async () => {
    prepararMaquinas({ personas: [0, 1], maquinas: [2, 3] });

    await expect(
      lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, {}),
    ).rejects.toMatchObject({ status: 409 });
    expect(insercion()).toBeUndefined();
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("409 si la plaza pedida ya está ocupada", async () => {
    prepararMaquinas({ personas: [0, 1] });

    await expect(
      lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, { posicion: 1 }),
    ).rejects.toMatchObject({ status: 409 });
  });

  it("400 con una dificultad desconocida, sin tocar la base de datos", async () => {
    await expect(
      lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, {
        dificultad: "imposible",
      }),
    ).rejects.toMatchObject({ status: 400 });
    expect(pool.connect).not.toHaveBeenCalled();
  });

  it("400 si la plaza no existe en una sala de 2", async () => {
    prepararMaquinas({ sala: { ...salaEsperando, capacidad: 2 } });

    await expect(
      lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, { posicion: 3 }),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("403 si no es el creador", async () => {
    prepararMaquinas({ sala: { ...salaEsperando, creador_id: OTRO_ID } });

    await expect(
      lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, {}),
    ).rejects.toMatchObject({ status: 403 });
  });

  it("409 si la partida ya ha empezado", async () => {
    prepararMaquinas({ sala: { ...salaEsperando, estado: "en_curso" } });

    await expect(
      lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, {}),
    ).rejects.toMatchObject({ status: 409 });
  });

  it("404 si la sala no existe", async () => {
    prepararMaquinas({ sala: null });

    await expect(
      lobbyService.anadirMaquina(SALA_ID, USUARIO_ID, {}),
    ).rejects.toMatchObject({ status: 404 });
  });

  it("quita la máquina de una plaza", async () => {
    prepararMaquinas({ personas: [0], maquinas: [] });

    const resultado = await lobbyService.quitarMaquina(SALA_ID, USUARIO_ID, 2);

    const borrado = cliente.query.mock.calls.find(([sql]) =>
      sql.includes("DELETE FROM sala_maquinas"),
    );
    expect(borrado[1]).toEqual([SALA_ID, 2]);
    expect(resultado.jugadores_actuales).toBe(1);
    expect(sqlsEjecutados()).toContain("COMMIT");
  });

  it("404 si en esa plaza no hay máquina", async () => {
    prepararMaquinas({ borradas: 0 });

    await expect(
      lobbyService.quitarMaquina(SALA_ID, USUARIO_ID, 2),
    ).rejects.toMatchObject({ status: 404 });
  });

  it("403 al quitar si no es el creador", async () => {
    prepararMaquinas({ sala: { ...salaEsperando, creador_id: OTRO_ID } });

    await expect(
      lobbyService.quitarMaquina(SALA_ID, USUARIO_ID, 2),
    ).rejects.toMatchObject({ status: 403 });
  });

  it("400 si la posición no es un número de 0 a 3", async () => {
    await expect(
      lobbyService.quitarMaquina(SALA_ID, USUARIO_ID, 7),
    ).rejects.toMatchObject({ status: 400 });
    await expect(
      lobbyService.quitarMaquina(SALA_ID, USUARIO_ID, NaN),
    ).rejects.toMatchObject({ status: 400 });
  });
});

describe("lobbyService.unirseSala con máquinas (PBI-20)", () => {
  const sala = {
    id: SALA_ID,
    juego: "guinote",
    estado: "esperando",
    capacidad: 4,
    creador_id: OTRO_ID,
    password_hash: null,
  };

  function prepararUnion(personas, maquinas) {
    cliente = {
      query: jest.fn(async (sql) => {
        if (sql.includes("FROM salas WHERE id")) return { rows: [sala] };
        if (sql.includes("FROM sala_participantes")) return { rows: personas };
        if (sql.includes("FROM sala_maquinas"))
          return { rows: maquinas.map((posicion) => ({ posicion })) };
        return { rows: [] };
      }),
      release: jest.fn(),
    };
    pool.connect.mockResolvedValue(cliente);
  }

  it("no sienta a nadie en una plaza que ocupa una máquina", async () => {
    prepararUnion([{ usuario_id: OTRO_ID, posicion: 0 }], [1]);

    await lobbyService.unirseSala(SALA_ID, USUARIO_ID);

    const insercion = cliente.query.mock.calls.find(([sql]) =>
      sql.includes("INSERT INTO sala_participantes"),
    );
    expect(insercion[1]).toEqual([SALA_ID, USUARIO_ID, 2]);
  });

  it("409 si entre personas y máquinas llenan la sala", async () => {
    prepararUnion([{ usuario_id: OTRO_ID, posicion: 0 }], [1, 2, 3]);

    await expect(
      lobbyService.unirseSala(SALA_ID, USUARIO_ID),
    ).rejects.toMatchObject({ status: 409 });
  });
});
