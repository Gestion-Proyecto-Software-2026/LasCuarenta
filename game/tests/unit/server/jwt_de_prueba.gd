extends RefCounted
## Firma JWT HS256 para los tests. El servidor nunca firma tokens: solo los
## verifica (VerificadorJwt), por eso esto vive en tests/.


static func firmar(payload: Dictionary, secreto: String, cabecera: Dictionary = {"alg": "HS256", "typ": "JWT"}) -> String:
	var contenido := _base64url(JSON.stringify(cabecera).to_utf8_buffer()) + "." \
		+ _base64url(JSON.stringify(payload).to_utf8_buffer())
	var firma := Crypto.new().hmac_digest(
		HashingContext.HASH_SHA256, secreto.to_utf8_buffer(), contenido.to_utf8_buffer())
	return contenido + "." + _base64url(firma)


static func _base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")
