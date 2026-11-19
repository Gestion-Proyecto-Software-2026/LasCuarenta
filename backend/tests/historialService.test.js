jest.mock("../src/models/db", () => ({ query: jest.fn(), connect: jest.fn() }));

const pool = require("../src/models/db");
const historialService = require("../src/services/historialService");

const YO = "22222222-2222-4222-8222-222222222222";
const OTRO = "33333333-3333-4333-8333-333333333333";
const TERCERO = "44444444-4444-4444-8444-444444444444";
const CUARTO = "55555555-5555-4555-8555-555555555555";
const PARTIDA_ID = "66666666-6666-4666-8666-666666666666";
const SALA_ID = "11111111-1111-4111-8111-111111111111";

function usuario(id, historialPublico = true, nombre = "Ana") {
  return { id, nombre_visible: nombre, historial_publico: historialPublico };
}

// Primera consulta: el usuario objetivo (control de acceso); segunda: sus datos.
function prepararConsultas(objetivo, filas = []) {
  pool.query
    .mockResolvedValueOnce({ rows: objetivo ? [objetivo] : [] })
    .mockResolvedValueOnce({ rows: filas });
}

// Fila tal como la devuelve la consulta del historial.
function filaHistorial(cambios = {}) {
  return {
    partida_id: PARTIDA_ID,
    sala_id: SALA_ID,
    juego: "guinote",
    fecha_inicio: new Date("2026-11-18T10:00:00Z"),
    fecha_fin: new Date("2026-11-18T10:24:13Z"),
    causa: "completa",
    motivo: "tantos",
    equipo: 0,
    gano: true,
    puntos_equipo: 105,
    puntos_rival: 52,
    num_jugadores: 4,
    otros: [
      { usuario_id: CUARTO, nombre_visible: "Pepe", posicion: 3, equipo: 1 },
      { usuario_id: TERCERO, nombre_visible: "Marta", posicion: 2, equipo: 0 },
      { usuario_id: OTRO, nombre_visible: "Luis", posicion: 1, equipo: 1 },
    ],
    ...cambios,
  };
}

// [{ juego, gano }] de la más reciente a la más antigua, a partir de "gV mD ...".
function partidas(texto) {
  const juegos = { g: "guinote", m: "mus", t: "tute" };
  return texto
    .split(" ")
    .map((p) => ({ juego: juegos[p[0]], gano: p[1] === "V" }));
}

beforeEach(() => {
  jest.clearAllMocks();
  pool.query.mockReset();
});

describe("historialService.formatearPartida", () => {
  it("reparte a los demás en compañeros y rivales, ordenados por posición y sin equipo", () => {
    const partida = historialService.formatearPartida(filaHistorial());

    expect(partida).toEqual({
      partida_id: PARTIDA_ID,
      sala_id: SALA_ID,
      juego: "guinote",
      num_jugadores: 4,
      fecha_inicio: new Date("2026-11-18T10:00:00Z"),
      fecha_fin: new Date("2026-11-18T10:24:13Z"),
      resultado: "victoria",
      gano: true,
      causa: "completa",
      motivo: "tantos",
      equipo: 0,
      puntos_equipo: 105,
      puntos_rival: 52,
      companeros: [
        { usuario_id: TERCERO, nombre_visible: "Marta", posicion: 2 },
      ],
      rivales: [
        { usuario_id: OTRO, nombre_visible: "Luis", posicion: 1 },
        { usuario_id: CUARTO, nombre_visible: "Pepe", posicion: 3 },
      ],
    });
  });

  it("una derrota del equipo 1 en el Mus a 2: sin compañeros y sin motivo", () => {
    const partida = historialService.formatearPartida(
      filaHistorial({
        juego: "mus",
        equipo: 1,
        gano: false,
        motivo: null,
        puntos_equipo: 1,
        puntos_rival: 2,
        num_jugadores: 2,
        otros: [
          { usuario_id: OTRO, nombre_visible: "Luis", posicion: 0, equipo: 0 },
        ],
      }),
    );

    expect(partida.resultado).toBe("derrota");
    expect(partida.gano).toBe(false);
    expect(partida.motivo).toBeNull();
    expect(partida.companeros).toEqual([]);
    expect(partida.rivales).toEqual([
      { usuario_id: OTRO, nombre_visible: "Luis", posicion: 0 },
    ]);
  });

  it("motivo ausente queda a null y sin otros jugadores devuelve listas vacías", () => {
    const fila = filaHistorial({ otros: null });
    delete fila.motivo;

    const partida = historialService.formatearPartida(fila);

    expect(partida.motivo).toBeNull();
    expect(partida.companeros).toEqual([]);
    expect(partida.rivales).toEqual([]);
  });

  it("deja al final a quien no tiene posicion (partidas anteriores a la migración)", () => {
    const partida = historialService.formatearPartida(
      filaHistorial({
        otros: [
          {
            usuario_id: CUARTO,
            nombre_visible: "Pepe",
            posicion: null,
            equipo: 1,
          },
          { usuario_id: OTRO, nombre_visible: "Luis", posicion: 1, equipo: 1 },
        ],
      }),
    );

    expect(partida.rivales.map((r) => r.usuario_id)).toEqual([OTRO, CUARTO]);
  });

  it("no modifica la fila recibida", () => {
    const fila = filaHistorial();
    const otrosAntes = fila.otros.map((o) => o.posicion);

    historialService.formatearPartida(fila);

    expect(fila.otros.map((o) => o.posicion)).toEqual(otrosAntes);
  });
});

describe("historialService.porcentajeVictorias", () => {
  it.each([
    [7, 12, 58.3],
    [5, 8, 62.5],
    [2, 4, 50],
    [2, 3, 66.7],
    [1, 3, 33.3],
    [5, 5, 100],
    [0, 4, 0],
    [0, 0, 0],
  ])("%i de %i → %p", (victorias, jugadas, esperado) => {
    expect(historialService.porcentajeVictorias(victorias, jugadas)).toBe(
      esperado,
    );
  });
});

describe("historialService.rachaActual", () => {
  it("sin partidas: tipo null y 0 partidas", () => {
    expect(historialService.rachaActual([])).toEqual({
      tipo: null,
      partidas: 0,
    });
  });

  it("cuenta los resultados iguales desde el más reciente", () => {
    expect(
      historialService.rachaActual([
        "victoria",
        "victoria",
        "derrota",
        "victoria",
      ]),
    ).toEqual({ tipo: "victoria", partidas: 2 });
    expect(
      historialService.rachaActual([
        "derrota",
        "derrota",
        "derrota",
        "victoria",
      ]),
    ).toEqual({ tipo: "derrota", partidas: 3 });
  });

  it("si todas son iguales, la racha es el total", () => {
    expect(historialService.rachaActual(["victoria", "victoria"])).toEqual({
      tipo: "victoria",
      partidas: 2,
    });
  });
});

describe("historialService.mejorRachaVictorias", () => {
  it.each([
    [[], 0],
    [["derrota", "derrota"], 0],
    [["victoria"], 1],
    [["victoria", "derrota", "victoria", "victoria", "victoria", "derrota"], 3],
    [["derrota", "victoria", "victoria", "derrota", "victoria"], 2],
    [["victoria", "victoria", "victoria", "victoria"], 4],
  ])("%j → %i", (resultados, esperado) => {
    expect(historialService.mejorRachaVictorias(resultados)).toBe(esperado);
  });
});

describe("historialService.calcularEstadisticas", () => {
  it("sin partidas: todo a cero, con los tres juegos", () => {
    expect(historialService.calcularEstadisticas([])).toEqual({
      totales: {
        jugadas: 0,
        victorias: 0,
        derrotas: 0,
        porcentaje_victorias: 0,
      },
      por_juego: [
        {
          juego: "guinote",
          jugadas: 0,
          victorias: 0,
          derrotas: 0,
          porcentaje_victorias: 0,
        },
        {
          juego: "mus",
          jugadas: 0,
          victorias: 0,
          derrotas: 0,
          porcentaje_victorias: 0,
        },
        {
          juego: "tute",
          jugadas: 0,
          victorias: 0,
          derrotas: 0,
          porcentaje_victorias: 0,
        },
      ],
      racha_actual: { tipo: null, partidas: 0 },
      mejor_racha_victorias: 0,
      ultimos_resultados: [],
    });
  });

  it("totales, por juego, rachas y últimos 10 de un historial de 12 partidas", () => {
    // De la más reciente a la más antigua: 3 victorias, 1 derrota, 4 victorias, 4 derrotas.
    const filas = partidas("gV mV gV gD gV gV mV gV gD mD gD mD");

    expect(historialService.calcularEstadisticas(filas)).toEqual({
      totales: {
        jugadas: 12,
        victorias: 7,
        derrotas: 5,
        porcentaje_victorias: 58.3,
      },
      por_juego: [
        {
          juego: "guinote",
          jugadas: 8,
          victorias: 5,
          derrotas: 3,
          porcentaje_victorias: 62.5,
        },
        {
          juego: "mus",
          jugadas: 4,
          victorias: 2,
          derrotas: 2,
          porcentaje_victorias: 50,
        },
        {
          juego: "tute",
          jugadas: 0,
          victorias: 0,
          derrotas: 0,
          porcentaje_victorias: 0,
        },
      ],
      racha_actual: { tipo: "victoria", partidas: 3 },
      mejor_racha_victorias: 4,
      ultimos_resultados: [
        "victoria",
        "victoria",
        "victoria",
        "derrota",
        "victoria",
        "victoria",
        "victoria",
        "victoria",
        "derrota",
        "derrota",
      ],
    });
  });

  it("racha actual de derrotas y solo partidas de Tute", () => {
    const estadisticas = historialService.calcularEstadisticas(
      partidas("tD tD tV"),
    );

    expect(estadisticas.racha_actual).toEqual({ tipo: "derrota", partidas: 2 });
    expect(estadisticas.mejor_racha_victorias).toBe(1);
    expect(estadisticas.por_juego.map((j) => j.juego)).toEqual([
      "guinote",
      "mus",
      "tute",
    ]);
    expect(estadisticas.por_juego[2]).toEqual({
      juego: "tute",
      jugadas: 3,
      victorias: 1,
      derrotas: 2,
      porcentaje_victorias: 33.3,
    });
    expect(estadisticas.ultimos_resultados).toEqual([
      "derrota",
      "derrota",
      "victoria",
    ]);
  });

  it("últimos resultados se queda en los 10 más recientes", () => {
    const filas = partidas("gD gV gV gV gV gV gV gV gV gV gD gD gD gD gD");

    const { ultimos_resultados } = historialService.calcularEstadisticas(filas);

    expect(ultimos_resultados).toHaveLength(10);
    expect(ultimos_resultados[0]).toBe("derrota");
    expect(ultimos_resultados.slice(1)).toEqual(Array(9).fill("victoria"));
  });
});

describe("historialService.listarHistorial", () => {
  it("con `me` consulta el historial del usuario del token, 100 como máximo y sin filtro", async () => {
    prepararConsultas(usuario(YO), [filaHistorial()]);

    const historial = await historialService.listarHistorial("me", YO, {});

    expect(historial).toEqual([
      historialService.formatearPartida(filaHistorial()),
    ]);
    expect(pool.query.mock.calls[0][1]).toEqual([YO]);
    const [sql, params] = pool.query.mock.calls[1];
    expect(params).toEqual([YO, null, 100]);
    expect(sql).toContain("ORDER BY p.fecha_fin DESC NULLS LAST, p.id DESC");
    expect(sql).toContain("json_agg");
  });

  it("sin query también funciona (valores por defecto)", async () => {
    prepararConsultas(usuario(YO), []);

    await expect(historialService.listarHistorial("me", YO)).resolves.toEqual(
      [],
    );
    expect(pool.query.mock.calls[1][1]).toEqual([YO, null, 100]);
  });

  it("devuelve las partidas en el orden en que llegan de la consulta", async () => {
    const reciente = filaHistorial({ partida_id: "b" });
    const antigua = filaHistorial({ partida_id: "a", gano: false });
    prepararConsultas(usuario(YO), [reciente, antigua]);

    const historial = await historialService.listarHistorial("me", YO, {});

    expect(historial.map((p) => [p.partida_id, p.resultado])).toEqual([
      ["b", "victoria"],
      ["a", "derrota"],
    ]);
  });

  it("filtra por juego y respeta el límite", async () => {
    prepararConsultas(usuario(YO), []);

    await historialService.listarHistorial("me", YO, {
      juego: "mus",
      limite: "25",
    });

    expect(pool.query.mock.calls[1][1]).toEqual([YO, "mus", 25]);
  });

  it("un juego o un límite vacíos cuentan como no enviados", async () => {
    prepararConsultas(usuario(YO), []);

    await historialService.listarHistorial("me", YO, { juego: "", limite: "" });

    expect(pool.query.mock.calls[1][1]).toEqual([YO, null, 100]);
  });

  it.each([["1"], ["500"]])("acepta el límite %s", async (limite) => {
    prepararConsultas(usuario(YO), []);

    await historialService.listarHistorial("me", YO, { limite });

    expect(pool.query.mock.calls[1][1][2]).toBe(Number(limite));
  });

  it("deja ver el historial público de otro usuario", async () => {
    prepararConsultas(usuario(OTRO, true, "Luis"), [filaHistorial()]);

    const historial = await historialService.listarHistorial(OTRO, YO, {});

    expect(historial).toHaveLength(1);
    expect(pool.query.mock.calls[0][1]).toEqual([OTRO]);
    expect(pool.query.mock.calls[1][1][0]).toBe(OTRO);
  });

  it("403 si el historial de otro usuario es privado, sin consultar sus partidas", async () => {
    prepararConsultas(usuario(OTRO, false), [filaHistorial()]);

    await expect(
      historialService.listarHistorial(OTRO, YO, {}),
    ).rejects.toMatchObject({
      status: 403,
      message: "este historial es privado",
    });
    expect(pool.query).toHaveBeenCalledTimes(1);
  });

  it("el titular ve su historial privado, también pidiéndolo por su UUID", async () => {
    prepararConsultas(usuario(YO, false), [filaHistorial()]);
    await expect(
      historialService.listarHistorial("me", YO, {}),
    ).resolves.toHaveLength(1);

    prepararConsultas(usuario(YO, false), [filaHistorial()]);
    await expect(
      historialService.listarHistorial(YO, YO, {}),
    ).resolves.toHaveLength(1);

    // PostgreSQL acepta el UUID en mayúsculas y devuelve el id en minúsculas.
    prepararConsultas(usuario(YO, false), []);
    await expect(
      historialService.listarHistorial(YO.toUpperCase(), YO, {}),
    ).resolves.toEqual([]);
  });

  it("404 si el usuario no existe", async () => {
    prepararConsultas(null);

    await expect(
      historialService.listarHistorial(OTRO, YO, {}),
    ).rejects.toMatchObject({ status: 404, message: "el usuario no existe" });
    expect(pool.query).toHaveBeenCalledTimes(1);
  });

  it.each([["abc"], ["123"], [""], ["ME"], [`${OTRO}x`]])(
    "400 si el id %p no es `me` ni un UUID, sin consultar la base de datos",
    async (id) => {
      await expect(
        historialService.listarHistorial(id, YO, {}),
      ).rejects.toMatchObject({
        status: 400,
        message: "id de usuario no válido",
      });
      expect(pool.query).not.toHaveBeenCalled();
    },
  );

  it.each([["poker"], ["Guinote"], [["mus", "tute"]]])(
    "400 si el juego %p no es válido, sin consultar la base de datos",
    async (juego) => {
      await expect(
        historialService.listarHistorial("me", YO, { juego }),
      ).rejects.toMatchObject({
        status: 400,
        message: "juego no válido, valores admitidos: guinote, mus, tute",
      });
      expect(pool.query).not.toHaveBeenCalled();
    },
  );

  it.each([
    ["0"],
    ["501"],
    ["abc"],
    ["1.5"],
    ["-3"],
    ["1e2"],
    [" 5"],
    [["1", "2"]],
  ])(
    "400 si el límite %p no es un entero de 1 a 500, sin consultar la base de datos",
    async (limite) => {
      await expect(
        historialService.listarHistorial("me", YO, { limite }),
      ).rejects.toMatchObject({
        status: 400,
        message: "limite no válido (entero de 1 a 500)",
      });
      expect(pool.query).not.toHaveBeenCalled();
    },
  );
});

describe("historialService.obtenerEstadisticas", () => {
  it("con `me` calcula las estadísticas del usuario del token", async () => {
    prepararConsultas(usuario(YO, true, "Ana"), partidas("gV mD gV"));

    const estadisticas = await historialService.obtenerEstadisticas("me", YO);

    expect(estadisticas).toEqual({
      usuario_id: YO,
      nombre_visible: "Ana",
      historial_publico: true,
      ...historialService.calcularEstadisticas(partidas("gV mD gV")),
    });
    const [sql, params] = pool.query.mock.calls[1];
    expect(params).toEqual([YO]);
    expect(sql).toContain("ORDER BY p.fecha_fin DESC NULLS LAST, p.id DESC");
  });

  it("de otro usuario con el historial público", async () => {
    prepararConsultas(usuario(OTRO, true, "Luis"), []);

    const estadisticas = await historialService.obtenerEstadisticas(OTRO, YO);

    expect(estadisticas.usuario_id).toBe(OTRO);
    expect(estadisticas.nombre_visible).toBe("Luis");
    expect(estadisticas.totales.jugadas).toBe(0);
    expect(pool.query.mock.calls[1][1]).toEqual([OTRO]);
  });

  it("el titular ve las suyas aunque su historial sea privado", async () => {
    prepararConsultas(usuario(YO, false), partidas("gV"));

    const estadisticas = await historialService.obtenerEstadisticas("me", YO);

    expect(estadisticas.historial_publico).toBe(false);
    expect(estadisticas.totales.victorias).toBe(1);
  });

  it("403 si son de otro usuario con el historial privado", async () => {
    prepararConsultas(usuario(OTRO, false), partidas("gV"));

    await expect(
      historialService.obtenerEstadisticas(OTRO, YO),
    ).rejects.toMatchObject({
      status: 403,
      message: "este historial es privado",
    });
    expect(pool.query).toHaveBeenCalledTimes(1);
  });

  it("404 si el usuario no existe", async () => {
    prepararConsultas(null);

    await expect(
      historialService.obtenerEstadisticas(OTRO, YO),
    ).rejects.toMatchObject({ status: 404, message: "el usuario no existe" });
  });

  it("400 si el id no es `me` ni un UUID, sin consultar la base de datos", async () => {
    await expect(
      historialService.obtenerEstadisticas("nadie", YO),
    ).rejects.toMatchObject({
      status: 400,
      message: "id de usuario no válido",
    });
    expect(pool.query).not.toHaveBeenCalled();
  });
});

describe("historialService.obtenerPrivacidad", () => {
  it("devuelve si el historial del usuario es público", async () => {
    pool.query.mockResolvedValueOnce({ rows: [{ historial_publico: false }] });

    await expect(historialService.obtenerPrivacidad(YO)).resolves.toEqual({
      historial_publico: false,
    });
    expect(pool.query.mock.calls[0][1]).toEqual([YO]);
  });

  it("404 si el usuario del token ya no existe", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    await expect(historialService.obtenerPrivacidad(YO)).rejects.toMatchObject({
      status: 404,
      message: "el usuario no existe",
    });
  });
});

describe("historialService.cambiarPrivacidad", () => {
  it.each([[true], [false]])("guarda historial_publico = %p", async (valor) => {
    pool.query.mockResolvedValueOnce({ rows: [{ historial_publico: valor }] });

    await expect(
      historialService.cambiarPrivacidad(YO, { historial_publico: valor }),
    ).resolves.toEqual({ historial_publico: valor });
    const [sql, params] = pool.query.mock.calls[0];
    expect(sql).toContain("UPDATE usuarios SET historial_publico");
    expect(params).toEqual([YO, valor]);
  });

  it("404 si el usuario del token ya no existe", async () => {
    pool.query.mockResolvedValueOnce({ rows: [] });

    await expect(
      historialService.cambiarPrivacidad(YO, { historial_publico: true }),
    ).rejects.toMatchObject({ status: 404, message: "el usuario no existe" });
  });

  it.each([["true"], [1], [0], [null], [undefined]])(
    "400 si historial_publico es %p, sin tocar la base de datos",
    async (valor) => {
      await expect(
        historialService.cambiarPrivacidad(YO, { historial_publico: valor }),
      ).rejects.toMatchObject({
        status: 400,
        message: "historial_publico tiene que ser true o false",
      });
      expect(pool.query).not.toHaveBeenCalled();
    },
  );

  it("400 sin body", async () => {
    await expect(historialService.cambiarPrivacidad(YO)).rejects.toMatchObject({
      status: 400,
    });
    expect(pool.query).not.toHaveBeenCalled();
  });
});
