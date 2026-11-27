# Créditos de los sonidos (PBI-21)

Todos los sonidos de esta carpeta son de **Kenney** ([kenney.nl](https://kenney.nl)) y tienen licencia **Creative Commons Zero (CC0 1.0)**, de dominio público: se pueden usar, modificar y redistribuir sin pedir permiso ni citar al autor. Aun así, aquí se cita la fuente de cada uno, como pide la PBI-21.

Licencia: <https://creativecommons.org/publicdomain/zero/1.0/>

| Fichero | Cuándo suena | Original | Paquete (fuente) |
|---|---|---|---|
| `repartir.ogg` | Al repartir una mano nueva (inicio de la partida, vuelta, mano nueva del Mus) | `card-shuffle.ogg` | [Casino Audio 1.1](https://kenney.nl/assets/casino-audio) |
| `robar_1.ogg` | Al robar una carta (una variante al azar) | `card-slide-1.ogg` | [Casino Audio 1.1](https://kenney.nl/assets/casino-audio) |
| `robar_2.ogg` | Ídem | `card-slide-2.ogg` | [Casino Audio 1.1](https://kenney.nl/assets/casino-audio) |
| `robar_3.ogg` | Ídem | `card-slide-3.ogg` | [Casino Audio 1.1](https://kenney.nl/assets/casino-audio) |
| `carta_1.ogg` | Al jugar una carta cualquier jugador (una variante al azar) | `card-place-1.ogg` | [Casino Audio 1.1](https://kenney.nl/assets/casino-audio) |
| `carta_2.ogg` | Ídem | `card-place-2.ogg` | [Casino Audio 1.1](https://kenney.nl/assets/casino-audio) |
| `carta_3.ogg` | Ídem | `card-place-3.ogg` | [Casino Audio 1.1](https://kenney.nl/assets/casino-audio) |
| `carta_4.ogg` | Ídem | `card-place-4.ogg` | [Casino Audio 1.1](https://kenney.nl/assets/casino-audio) |
| `turno.ogg` | Cuando le toca jugar o decidir al jugador | `confirmation_001.ogg` | [Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds) |

Los ficheros son los originales, sin modificar, solo renombrados. Pesan unos 105 KB en total (el límite de la PBI-21 es de 5 MB; lo comprueba `tests/unit/client/test_sonidos.gd`).

Para añadir o cambiar un sonido: que tenga licencia libre, añadir su fila a esta tabla y su ruta a `client/autoload/sonidos.gd`.
