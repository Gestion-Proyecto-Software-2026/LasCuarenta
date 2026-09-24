class_name VerificadorJwt
extends RefCounted
## Verifica los JWT que firma el backend (jsonwebtoken, HS256) con el mismo
## JWT_SECRET, para validar [code]unirse_partida[/code] sin preguntar al backend
## (analisis_funcional_app.md §6).
##
## Solo se acepta HS256: un token con otro [code]alg[/code] (incluido
## [code]none[/code]) se rechaza aunque su firma cuadre.

static var _base64url := RegEx.create_from_string("^[A-Za-z0-9_-]+$")


## Devuelve el payload del token si la firma es correcta y no ha caducado
## ([code]exp[/code]), o [code]{}[/code] si no es válido.
## [param ahora_unix] solo lo pasan los tests; por defecto, la hora del sistema.
static func verificar(token: String, secreto: String, ahora_unix: int = -1) -> Dictionary:
	if secreto.is_empty():
		return {}
	var partes := token.split(".")
	if partes.size() != 3:
		return {}
	var cabecera: Variant = _json_de_base64url(partes[0])
	if not cabecera is Dictionary or cabecera.get("alg") != "HS256":
		return {}

	var firma := _bytes_de_base64url(partes[2])
	var firma_esperada := Crypto.new().hmac_digest(
		HashingContext.HASH_SHA256,
		secreto.to_utf8_buffer(),
		(partes[0] + "." + partes[1]).to_utf8_buffer())
	if firma.size() != firma_esperada.size() or not Crypto.new().constant_time_compare(firma, firma_esperada):
		return {}

	var payload: Variant = _json_de_base64url(partes[1])
	if not payload is Dictionary:
		return {}
	if payload.has("exp"):
		var exp: Variant = payload["exp"]
		var ahora := ahora_unix if ahora_unix >= 0 else int(Time.get_unix_time_from_system())
		if not (exp is float or exp is int) or ahora >= int(exp):
			return {}
	return payload


static func _bytes_de_base64url(texto: String) -> PackedByteArray:
	if _base64url.search(texto) == null or texto.length() % 4 == 1:
		return PackedByteArray()
	var base64 := texto.replace("-", "+").replace("_", "/")
	while base64.length() % 4 != 0:
		base64 += "="
	return Marshalls.base64_to_raw(base64)


static func _json_de_base64url(texto: String) -> Variant:
	var bytes := _bytes_de_base64url(texto)
	if bytes.is_empty():
		return null
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return null
	return json.data
