extends Node




# Función reutilizable para lanzar 1 o N tweens a la vez
func lanzar_tweens_simultaneos(animaciones: Array, objetivo: Node = self) -> Tween:
	# 1. Creamos el tween
	var tween = create_tween()
	
	# 2. Le decimos que ejecute todas las animaciones a la vez (en paralelo)
	tween.set_parallel(true)
	
	# 3. Recorremos el array y creamos un tween_property por cada configuración
	for anim in animaciones:
		var prop = anim.get("prop", "")
		var valor = anim.get("valor", null)
		var duracion = anim.get("dur", 0.2) # 0.2 segundos por defecto
		
		if prop != "" and valor != null:
			var t = tween.tween_property(objetivo, prop, valor, duracion)
			
			# Opcional: Si le pasamos un tipo de transición o suavizado (ease), lo aplicamos
			if anim.has("trans"): t.set_trans(anim["trans"])
			if anim.has("ease"): t.set_ease(anim["ease"])
			
	return tween # Lo devolvemos por si en algún momento quieres usar "await tween.finished"
	
	
	#USO==========================================
	#lanzar_tweens_simultaneos([
				#{"prop": "scale", "valor": Vector2(1.0, 1.0), "dur": 0.2, "trans": Tween.TRANS_SINE},
				#{"prop": "modulate", "valor": Color(1, 1, 1, 1), "dur": 0.2}
			#], self)
	
