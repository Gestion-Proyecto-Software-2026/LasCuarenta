#!/usr/bin/env bash
# Partidas completas por red, sin pantalla: en cada caso arranca un servidor y
# los clientes que pida el modo, que juegan solos (autojugar), y comprueba que
# la partida termina bien en todos.
#
# Uso (desde cualquier carpeta):
#   GODOT=/ruta/a/godot game/herramientas/partidas_red.sh                    # un caso por modo
#   GODOT=/ruta/a/godot game/herramientas/partidas_red.sh "mus_2v2:3 tute_1v1:5:no_cantar"
#
# Cada caso es MODO:SEMILLA[:no_cantar], con MODO uno de compartido/logica/modos.gd.
# En Windows, GODOT es la variante _console.exe para ver la salida.
#
# Una partida va bien si: el servidor escribe su línea "FIN …", todos los
# clientes reciben el resultado, no hay errores de script y, en los juegos de
# bazas, las cartas de las idas suman 120 (salvo si se acaba antes por Tute o
# capote). Devuelve 1 si alguna falla. Los registros quedan en $REGISTROS.

GODOT="${GODOT:-godot}"
PUERTO="${PUERTO_INICIAL:-9500}"
REGISTROS="${REGISTROS:-$(mktemp -d)}"
CASOS="${1:-guinote_1v1:1 guinote_2v2:1 tute_1v1:1 tute_2v2:1 mus_1v1:1 mus_2v2:1}"

cd "$(dirname "$0")/.." || exit 1
# Sin importar antes, Godot no conoce las clases del proyecto (ver README §7).
"$GODOT" --headless --path . --import > "$REGISTROS/import.log" 2>&1

bien=0
mal=0
for caso in $CASOS; do
	IFS=: read -r modo semilla extra <<< "$caso"
	jugadores=2
	[[ "$modo" == *2v2 ]] && jugadores=4
	PUERTO=$((PUERTO + 1))
	dir="$REGISTROS/${caso//:/_}"
	mkdir -p "$dir"

	"$GODOT" --headless --path . res://escenas/partida.tscn -- \
		modo="$modo" servidor pausa_corta salir_al_terminar limite=240 puerto="$PUERTO" semilla="$semilla" \
		> "$dir/servidor.log" 2>&1 &
	for i in $(seq 1 "$jugadores"); do
		"$GODOT" --headless --path . res://escenas/partida.tscn -- \
			modo="$modo" cliente autojugar salir_al_terminar limite=240 puerto="$PUERTO" $extra \
			> "$dir/cliente$i.log" 2>&1 &
	done
	wait

	fin=$(grep -m1 "^FIN " "$dir/servidor.log")
	# El aviso de ENet al cerrarse las ventanas no es un fallo de la partida.
	errores=$(cat "$dir"/*.log | grep -iE "SCRIPT ERROR|ERROR:|Parse Error|Invalid call|Invalid access" \
		| grep -vc "Unable to send packet")
	con_resultado=$(grep -l "FIN DE LA PARTIDA" "$dir"/cliente*.log 2>/dev/null | wc -l)
	cartas=$(echo "$fin" | sed -n 's/.*cartas=\([0-9]*\)-\([0-9]*\).*/\1 \2/p')
	suma=0
	[ -n "$cartas" ] && suma=$(( ${cartas% *} + ${cartas#* } ))

	resultado="MAL"
	if [ -n "$fin" ] && [ "$errores" -eq 0 ] && [ "$con_resultado" -eq "$jugadores" ]; then
		if [ "$suma" -eq 120 ] || [[ "$fin" =~ motivo=(tute|capote) ]] || [[ "$fin" =~ juegos=(2-[01]|[01]-2) ]]; then
			resultado="BIEN"
		fi
	fi
	if [ "$resultado" = "BIEN" ]; then bien=$((bien + 1)); else mal=$((mal + 1)); fi
	echo "[$resultado] $caso | clientes con resultado: $con_resultado/$jugadores | errores: $errores"
	echo "        ${fin:-(el servidor no escribió el final)}"
done

echo "TOTAL: $bien bien, $mal mal. Registros en $REGISTROS"
[ "$mal" -eq 0 ]
