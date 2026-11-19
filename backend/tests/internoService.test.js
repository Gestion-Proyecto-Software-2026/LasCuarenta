jest.mock("../src/models/db", () => ({ query: jest.fn(), connect: jest.fn() }));

const pool = require("../src/models/db");
const internoService = require("../src/services/internoService");

const SALA_ID = "11111111-1111-4111-8111-111111111111";
const USUARIO_ID = "22222222-2222-4222-8222-222222222222";
const OTRO_ID = "44444444-4444-4444-8444-444444444444";
const PARTIDA_ID = "33333333-3333-4333-8333-333333333333";

let cliente;

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

beforeEach(() => {
  jest.clearAllMocks();
});

describe("internoService.obtenerSala", () => {
  it("devuelve la sala con los participantes y su equipo calculado", async () => {
    pool.query
      .mockResolvedValueOnce({
        rows: [
          { id: SALA_ID, juego: "guinote", estado: "esperando", capacidad: 4 },
        ],
      })
      .mockResolvedValueOnce({
        rows: [
          { usuario_id: USUARIO_ID, posicion: 0, nombre_visible: "Ana" },
          { usuario_id: "otro", posicion: 1, nombre_visible: "Luis" },
        ],
      });

    const sala = await internoService.obtenerSala(SALA_ID);

    expect(sala).toEqual({
      id: SALA_ID,
      juego: "guinote",
      estado: "esperando",
      capacidad: 4,
      participantes: [
        {
          usuario_id: USUARIO_ID,
          posicion: 0,
          equipo: 0,
          nombre_visible: "Ana",
        },
        { usuario_id: "otro", posicion: 1, equipo: 1, nombre_visible: "Luis" },
      ],
    });
  });

  it("404 si la sala no existe", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    await expect(internoService.obtenerSala(SALA_ID)).rejects.toMatchObject({
      status: 404,
    });
  });

  it("400 si el id no es un UUID", async () => {
    await expect(
      internoService.obtenerSala("no-es-uuid"),
    ).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.query).not.toHaveBeenCalled();
  });
});

describe("internoService.registrarPartida", () => {
  const jugadores = [
    { usuario_id: USUARIO_ID, posicion: 0, equipo: 0 },
    { usuario_id: OTRO_ID, posicion: 1, equipo: 1 },
  ];
  const resultado = { equipo_ganador: 0, puntos_por_equipo: [101, 54] };

  function sqlsEjecutados() {
    return cliente.query.mock.calls.map(([sql]) => sql.trim());
  }

  function insertDePartida() {
    return cliente.query.mock.calls.find(([sql]) =>
      sql.includes("INSERT INTO partidas"),
    );
  }

  function insertsDeJugador() {
    return cliente.query.mock.calls.filter(([sql]) =>
      sql.includes("INSERT INTO partida_jugadores"),
    );
  }

  function prepararSalaGuinote() {
    prepararCliente({
      "FROM salas WHERE id": [{ id: SALA_ID, juego: "guinote" }],
      "INSERT INTO partidas": [{ id: PARTIDA_ID }],
    });
  }

  // Un body que no pasa la validación: 400 sin abrir siquiera la transacción.
  async function esperar400(body, mensaje) {
    const promesa = internoService.registrarPartida(body);
    await expect(promesa).rejects.toMatchObject({ status: 400 });
    await expect(promesa).rejects.toThrow(mensaje);
    expect(pool.connect).not.toHaveBeenCalled();
  }

  it("inserta la partida, a cada jugador y cierra la sala, en una transacción", async () => {
    prepararSalaGuinote();

    const partida = await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado,
    });

    expect(partida).toEqual({ id: PARTIDA_ID });

    const sqls = sqlsEjecutados();
    expect(sqls[0]).toBe("BEGIN");
    expect(sqls.at(-1)).toBe("COMMIT");
    expect(
      sqls.some((s) => s.includes("UPDATE salas SET estado = 'finalizada'")),
    ).toBe(true);

    const insertsJugador = insertsDeJugador();
    expect(insertsJugador).toHaveLength(2);
    // [partida_id, usuario_id, equipo, posicion, puntos_obtenidos, gano]
    expect(insertsJugador[0][1]).toEqual([
      PARTIDA_ID,
      USUARIO_ID,
      0,
      0,
      101,
      true,
    ]);
    expect(insertsJugador[1][1]).toEqual([
      PARTIDA_ID,
      OTRO_ID,
      1,
      1,
      54,
      false,
    ]);
    expect(cliente.release).toHaveBeenCalledTimes(1);
  });

  it("guarda la posicion de cada jugador aunque no vengan en orden", async () => {
    prepararCliente({
      "FROM salas WHERE id": [{ id: SALA_ID, juego: "mus" }],
      "INSERT INTO partidas": [{ id: PARTIDA_ID }],
    });

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores: [
        { usuario_id: OTRO_ID, posicion: 3, equipo: 1 },
        { usuario_id: USUARIO_ID, posicion: 2, equipo: 0 },
      ],
      resultado: { equipo_ganador: 1, puntos_por_equipo: [1, 2] },
    });

    const insertsJugador = insertsDeJugador();
    expect(insertsJugador[0][0]).toContain("posicion");
    expect(insertsJugador[0][1]).toEqual([PARTIDA_ID, OTRO_ID, 1, 3, 2, true]);
    expect(insertsJugador[1][1]).toEqual([
      PARTIDA_ID,
      USUARIO_ID,
      0,
      2,
      1,
      false,
    ]);
  });

  it("sin puntos_por_equipo, cada jugador queda con 0 puntos", async () => {
    prepararSalaGuinote();

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado: { equipo_ganador: 1 },
    });

    expect(insertsDeJugador().map(([, params]) => params[4])).toEqual([0, 0]);
  });

  it("guarda la causa (completa por defecto) y el resultado tal cual llega", async () => {
    prepararSalaGuinote();

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado,
    });

    const [sql, params] = insertDePartida();
    expect(sql).toContain("causa");
    expect(params[5]).toBe("completa");
    expect(JSON.parse(params[4])).toEqual(resultado);
  });

  it("guarda la causa renuncio cuando viene en el resultado", async () => {
    prepararSalaGuinote();

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado: { ...resultado, causa: "renuncio" },
    });

    expect(insertDePartida()[1][5]).toBe("renuncio");
  });

  it("guarda las fechas reales de inicio y fin, normalizadas a UTC", async () => {
    prepararSalaGuinote();

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado,
      fecha_inicio: "2026-11-18T11:00:00+01:00",
      fecha_fin: "2026-11-18T10:24:13Z",
    });

    const params = insertDePartida()[1];
    expect(params[2]).toBe("2026-11-18T10:00:00.000Z");
    expect(params[3]).toBe("2026-11-18T10:24:13.000Z");
  });

  it("sin fechas, deja que la base de datos ponga now() en las dos", async () => {
    prepararSalaGuinote();

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado,
    });

    const [sql, params] = insertDePartida();
    expect(params[2]).toBeNull();
    expect(params[3]).toBeNull();
    // fecha_inicio cae en fecha_fin y, si tampoco está, en now().
    expect(sql).toContain("COALESCE($3::timestamptz, $4::timestamptz, now())");
    expect(sql).toContain("COALESCE($4::timestamptz, now())");
  });

  it("con solo fecha_fin, fecha_inicio va a null para que tome la de fin", async () => {
    prepararSalaGuinote();

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado,
      fecha_fin: "2026-11-18T10:24:13Z",
    });

    const params = insertDePartida()[1];
    expect(params[2]).toBeNull();
    expect(params[3]).toBe("2026-11-18T10:24:13.000Z");
  });

  it("acepta fecha_inicio igual a fecha_fin", async () => {
    prepararSalaGuinote();

    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado,
        fecha_inicio: "2026-11-18T10:00:00Z",
        fecha_fin: "2026-11-18T10:00:00Z",
      }),
    ).resolves.toEqual({ id: PARTIDA_ID });
  });

  it("acepta fechas de los años 1 y 9999 en UTC, los extremos que PostgreSQL lee", async () => {
    prepararSalaGuinote();

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado,
      fecha_inicio: "0001-01-01T00:00:00Z",
      fecha_fin: "9999-12-31T23:59:59Z",
    });

    const params = insertDePartida()[1];
    expect(params[2]).toBe("0001-01-01T00:00:00.000Z");
    expect(params[3]).toBe("9999-12-31T23:59:59.000Z");
  });

  it("acepta en resultado textos con acentos y emojis (pares UTF-16 bien formados)", async () => {
    prepararSalaGuinote();

    await internoService.registrarPartida({
      sala_id: SALA_ID,
      jugadores,
      resultado: { ...resultado, nota: "Guiñote 🂡" },
    });

    expect(JSON.parse(insertDePartida()[1][4]).nota).toBe("Guiñote 🂡");
  });

  it("404 si la sala no existe, y hace ROLLBACK", async () => {
    prepararCliente({ "FROM salas WHERE id": [] });

    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado,
      }),
    ).rejects.toMatchObject({ status: 404, message: "la sala no existe" });

    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("409 si la partida de esa sala ya está registrada, sin insertar nada", async () => {
    prepararCliente({
      "FROM salas WHERE id": [{ id: SALA_ID, juego: "guinote" }],
      "FROM partidas WHERE sala_id": [{ id: PARTIDA_ID }],
    });

    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado,
      }),
    ).rejects.toMatchObject({
      status: 409,
      message: "la partida de esta sala ya está registrada",
    });

    const sqls = sqlsEjecutados();
    expect(sqls.some((s) => s.includes("INSERT"))).toBe(false);
    expect(sqls.some((s) => s.includes("UPDATE salas"))).toBe(false);
    expect(sqls).toContain("ROLLBACK");
    expect(cliente.release).toHaveBeenCalledTimes(1);
  });

  it("409 si salta el índice único de la sala (23505)", async () => {
    const duplicado = Object.assign(new Error("duplicate key"), {
      code: "23505",
      constraint: "partidas_sala_unica",
    });
    prepararCliente({
      "FROM salas WHERE id": [{ id: SALA_ID, juego: "guinote" }],
      "INSERT INTO partidas": duplicado,
    });

    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado,
      }),
    ).rejects.toMatchObject({
      status: 409,
      message: "la partida de esta sala ya está registrada",
    });
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("un 23505 de otra restricción no se confunde con una partida ya registrada", async () => {
    const otro = Object.assign(new Error("duplicate key"), {
      code: "23505",
      constraint: "partida_jugadores_pkey",
    });
    prepararCliente({
      "FROM salas WHERE id": [{ id: SALA_ID, juego: "guinote" }],
      "INSERT INTO partidas": [{ id: PARTIDA_ID }],
      "INSERT INTO partida_jugadores": otro,
    });

    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado,
      }),
    ).rejects.toBe(otro);
  });

  it("400 si algún usuario_id no corresponde a ninguna cuenta (23503)", async () => {
    const claveForanea = Object.assign(new Error("foreign key"), {
      code: "23503",
    });
    prepararCliente({
      "FROM salas WHERE id": [{ id: SALA_ID, juego: "guinote" }],
      "INSERT INTO partidas": [{ id: PARTIDA_ID }],
      "INSERT INTO partida_jugadores": claveForanea,
    });

    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado,
      }),
    ).rejects.toMatchObject({
      status: 400,
      message: "algún jugador no existe",
    });
    expect(sqlsEjecutados()).toContain("ROLLBACK");
  });

  it("cualquier otro error de la base de datos se propaga tras el ROLLBACK", async () => {
    const caido = new Error("conexión perdida");
    prepararCliente({
      "FROM salas WHERE id": [{ id: SALA_ID, juego: "guinote" }],
      "INSERT INTO partidas": caido,
    });

    await expect(
      internoService.registrarPartida({
        sala_id: SALA_ID,
        jugadores,
        resultado,
      }),
    ).rejects.toBe(caido);
    expect(sqlsEjecutados()).toContain("ROLLBACK");
    expect(cliente.release).toHaveBeenCalledTimes(1);
  });

  describe("validación del body (400 sin tocar la base de datos)", () => {
    it("sala_id que no es un UUID", async () => {
      await esperar400(
        { sala_id: "x", jugadores, resultado },
        "sala_id no válido",
      );
    });

    it("jugadores que no es un array", async () => {
      await esperar400(
        { sala_id: SALA_ID, jugadores: null, resultado },
        "jugadores debe ser un array no vacío",
      );
    });

    it("jugadores vacío", async () => {
      await esperar400(
        { sala_id: SALA_ID, jugadores: [], resultado },
        "jugadores debe ser un array no vacío",
      );
    });

    it("un jugador que no es un objeto", async () => {
      await esperar400(
        { sala_id: SALA_ID, jugadores: [null], resultado },
        "cada jugador necesita usuario_id, posicion y equipo",
      );
    });

    it.each([
      ["vacío (asiento sin nadie)", ""],
      ["que no es un UUID", "u1"],
      ["que no es una cadena", 7],
      ["ausente", undefined],
    ])("usuario_id %s", async (_caso, usuarioId) => {
      await esperar400(
        {
          sala_id: SALA_ID,
          jugadores: [{ usuario_id: usuarioId, posicion: 0, equipo: 0 }],
          resultado,
        },
        "usuario_id de jugador no válido",
      );
    });

    it.each([[-1], [4], [1.5], ["0"], [undefined]])(
      "posicion %p fuera de 0 a 3",
      async (posicion) => {
        await esperar400(
          {
            sala_id: SALA_ID,
            jugadores: [{ usuario_id: USUARIO_ID, posicion, equipo: 0 }],
            resultado,
          },
          "posicion de jugador no válida (entero de 0 a 3)",
        );
      },
    );

    it.each([[-1], [2], [0.5], ["1"], [null]])(
      "equipo %p que no es 0 ni 1",
      async (equipo) => {
        await esperar400(
          {
            sala_id: SALA_ID,
            jugadores: [{ usuario_id: USUARIO_ID, posicion: 0, equipo }],
            resultado,
          },
          "equipo de jugador no válido (0 o 1)",
        );
      },
    );

    it("un usuario_id repetido (aunque cambien las mayúsculas)", async () => {
      await esperar400(
        {
          sala_id: SALA_ID,
          jugadores: [
            { usuario_id: USUARIO_ID, posicion: 0, equipo: 0 },
            { usuario_id: USUARIO_ID.toUpperCase(), posicion: 1, equipo: 1 },
          ],
          resultado,
        },
        "un jugador aparece más de una vez",
      );
    });

    it("dos jugadores en la misma posicion", async () => {
      await esperar400(
        {
          sala_id: SALA_ID,
          jugadores: [
            { usuario_id: USUARIO_ID, posicion: 1, equipo: 1 },
            { usuario_id: OTRO_ID, posicion: 1, equipo: 1 },
          ],
          resultado,
        },
        "dos jugadores en la misma posicion",
      );
    });

    it.each([
      ["ausente", undefined],
      ["a null", null],
      ["que es un array", [0, [101, 54]]],
      ["que es un texto", "victoria"],
    ])("resultado %s", async (_caso, valor) => {
      await esperar400(
        { sala_id: SALA_ID, jugadores, resultado: valor },
        "resultado es obligatorio",
      );
    });

    it.each([[undefined], [2], [-1], [0.5], ["0"]])(
      "resultado.equipo_ganador %p",
      async (equipoGanador) => {
        await esperar400(
          {
            sala_id: SALA_ID,
            jugadores,
            resultado: { equipo_ganador: equipoGanador },
          },
          "resultado.equipo_ganador tiene que ser 0 o 1",
        );
      },
    );

    it.each([
      ["que no es un array", "105-52"],
      ["con un solo equipo", [105]],
      ["con tres equipos", [1, 2, 3]],
      ["con un número negativo", [105, -1]],
      ["con decimales", [10.5, 52]],
      ["con un texto", ["105", 52]],
      ["a null", null],
    ])("resultado.puntos_por_equipo %s", async (_caso, puntos) => {
      await esperar400(
        {
          sala_id: SALA_ID,
          jugadores,
          resultado: { equipo_ganador: 0, puntos_por_equipo: puntos },
        },
        "resultado.puntos_por_equipo tiene que ser un array de 2 enteros no negativos",
      );
    });

    it.each([["desconocida"], [""], [null], [1]])(
      "resultado.causa %p",
      async (causa) => {
        await esperar400(
          {
            sala_id: SALA_ID,
            jugadores,
            resultado: { ...resultado, causa },
          },
          "resultado.causa no válida, valores admitidos: completa, renuncio",
        );
      },
    );

    it.each([
      ["que no se puede leer", "ayer por la tarde"],
      ["sin hora", "2026-11-18"],
      ["sin zona horaria", "2026-11-18T10:00:00"],
      ["con una hora imposible", "2026-11-18T25:00:00Z"],
      ["que no es una cadena", 1794996000000],
    ])("fecha %s", async (_caso, fecha) => {
      await esperar400(
        { sala_id: SALA_ID, jugadores, resultado, fecha_inicio: fecha },
        "fecha_inicio no válida (se espera una fecha ISO 8601 con zona horaria)",
      );
      await esperar400(
        { sala_id: SALA_ID, jugadores, resultado, fecha_fin: fecha },
        "fecha_fin no válida (se espera una fecha ISO 8601 con zona horaria)",
      );
    });

    // PostgreSQL no tiene año 0 ni lee los años de 5 cifras de toISOString.
    it.each([
      ["en el año 0", "0000-01-01T00:00:00Z"],
      ["que en UTC cae antes del año 1", "0000-01-01T00:30:00+01:00"],
      ["que en UTC pasa al año 10000", "9999-12-31T23:00:00-05:00"],
    ])("fecha %s", async (_caso, fecha) => {
      await esperar400(
        { sala_id: SALA_ID, jugadores, resultado, fecha_inicio: fecha },
        "fecha_inicio fuera de rango (el año, en UTC, tiene que ir de 1 a 9999)",
      );
      await esperar400(
        { sala_id: SALA_ID, jugadores, resultado, fecha_fin: fecha },
        "fecha_fin fuera de rango (el año, en UTC, tiene que ir de 1 a 9999)",
      );
    });

    // JSONB los rechaza, y sería un 500 que el servidor de partida reintentaría.
    it.each([
      ["un carácter nulo en un texto", { motivo: "a\u0000b" }],
      ["un carácter nulo en una clave", { "a\u0000b": 1 }],
      ["un carácter nulo dentro de un array", { manos: [{ x: "\u0000" }] }],
      ["un sustituto UTF-16 suelto", { motivo: "\ud800" }],
    ])("resultado con %s", async (_caso, extra) => {
      await esperar400(
        { sala_id: SALA_ID, jugadores, resultado: { ...resultado, ...extra } },
        "resultado contiene caracteres que no se pueden guardar (\\u0000 o UTF-16 mal formado)",
      );
    });

    it("fecha_inicio posterior a fecha_fin", async () => {
      await esperar400(
        {
          sala_id: SALA_ID,
          jugadores,
          resultado,
          fecha_inicio: "2026-11-18T10:24:14Z",
          fecha_fin: "2026-11-18T10:24:13Z",
        },
        "fecha_inicio no puede ser posterior a fecha_fin",
      );
    });
  });
});
