extends GutTest
## Los tokens fijos están generados con jsonwebtoken (la librería del backend),
## para comprobar que el servidor acepta exactamente lo que firma el backend.

const JwtDePrueba := preload("res://tests/unit/server/jwt_de_prueba.gd")
const SECRETO := "secreto_de_prueba"
const USUARIO := "1b4e28ba-2fa1-11d2-883f-0016d3cca427"

# jwt.sign({ id }, SECRETO, { noTimestamp: true })
const TOKEN_SIN_EXP := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjFiNGUyOGJhLTJmYTEtMTFkMi04ODNmLTAwMTZkM2NjYTQyNyJ9.VlMA_OauaZe1bkxLCsf0VoDIlzAsea8cCyAbMm6QUkk"
# jwt.sign({ id, exp: 4102444800 }, SECRETO, ...) — caduca en 2100
const TOKEN_EXP_2100 := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjFiNGUyOGJhLTJmYTEtMTFkMi04ODNmLTAwMTZkM2NjYTQyNyIsImV4cCI6NDEwMjQ0NDgwMH0.3cZbhzbhKROO4urhKVAvSv7pOH7pKXX0HOLKQ4K3HeE"
# jwt.sign({ id, exp: 1000000000 }, SECRETO, ...) — caducó en 2001
const TOKEN_CADUCADO := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjFiNGUyOGJhLTJmYTEtMTFkMi04ODNmLTAwMTZkM2NjYTQyNyIsImV4cCI6MTAwMDAwMDAwMH0.bxQWWUxENO9Jf1-UvQKtai62Jqvzn8ce7d8Z9iHzUPk"
# jwt.sign({ id }, "otro", ...)
const TOKEN_OTRO_SECRETO := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjFiNGUyOGJhLTJmYTEtMTFkMi04ODNmLTAwMTZkM2NjYTQyNyJ9.3FbkDkEPJAd8XhYtP9CN4QDJnrX2GoffGwkPHpnWs-I"
# jwt.sign({ id }, SECRETO, { algorithm: "HS512" })
const TOKEN_HS512 := "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjFiNGUyOGJhLTJmYTEtMTFkMi04ODNmLTAwMTZkM2NjYTQyNyJ9.yLFFoUnIuWlJU5KNWWY-skEBCeIj0iQrrjaq13nan1dtk5cRR-4YlY2qN97Mf8E48VLgPWGujA-Jt_Z0nUJh1A"


func test_acepta_tokens_de_jsonwebtoken() -> void:
	assert_eq(VerificadorJwt.verificar(TOKEN_SIN_EXP, SECRETO).get("id"), USUARIO)
	assert_eq(VerificadorJwt.verificar(TOKEN_EXP_2100, SECRETO).get("id"), USUARIO)


func test_rechaza_token_caducado() -> void:
	assert_eq(VerificadorJwt.verificar(TOKEN_CADUCADO, SECRETO), {})
	assert_eq(VerificadorJwt.verificar(TOKEN_EXP_2100, SECRETO, 4102444800), {}, "justo en exp ya no vale")


func test_rechaza_otro_secreto_y_secreto_vacio() -> void:
	assert_eq(VerificadorJwt.verificar(TOKEN_OTRO_SECRETO, SECRETO), {})
	assert_eq(VerificadorJwt.verificar(TOKEN_SIN_EXP, ""), {})


func test_rechaza_algoritmos_distintos_de_hs256() -> void:
	assert_eq(VerificadorJwt.verificar(TOKEN_HS512, SECRETO), {})
	var sin_firma := JwtDePrueba.firmar({"id": USUARIO}, SECRETO, {"alg": "none"})
	assert_eq(VerificadorJwt.verificar(sin_firma, SECRETO), {})


func test_rechaza_payload_manipulado() -> void:
	var partes := TOKEN_SIN_EXP.split(".")
	var otro_payload := Marshalls.utf8_to_base64('{"id":"otro-usuario"}').replace("=", "")
	assert_eq(VerificadorJwt.verificar(partes[0] + "." + otro_payload + "." + partes[2], SECRETO), {})


func test_rechaza_tokens_mal_formados() -> void:
	for token in ["", "abc", "a.b", "a.b.c.d", "###.###.###", "..", "e.e.e"]:
		assert_eq(VerificadorJwt.verificar(token, SECRETO), {}, "'%s'" % token)


func test_helper_de_tests_firma_igual_que_jsonwebtoken() -> void:
	assert_eq(JwtDePrueba.firmar({"id": USUARIO}, SECRETO), TOKEN_SIN_EXP)
