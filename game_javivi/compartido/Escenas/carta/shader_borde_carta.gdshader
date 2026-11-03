shader_type canvas_item;

// Parámetros modificables desde el Inspector
uniform float radio_esquina : hint_range(0.0, 1.0) = 0.2;
uniform float opacidad_centro : hint_range(0.0, 1.0) = 0.8;
uniform float opacidad_borde : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    // Normalizar las coordenadas UV al rango [-1, 1] desde el centro
    vec2 uv = UV * 2.0 - 1.0;
    
    // --- LÓGICA DE BORDES REDONDEADOS ---
    // Calculamos la distancia hacia las esquinas
    vec2 abs_uv = abs(uv) - (1.0 - radio_esquina);
    float dist_esquina = length(max(abs_uv, 0.0)) - radio_esquina;
    
    // Si la distancia es mayor a 0, estamos fuera del borde redondeado (hacemos invisible)
    if (dist_esquina > 0.0) {
        discard;
    }
    
    // --- LÓGICA DE OPACIDAD (Más opaco al centro, más transparente al borde) ---
    // Medimos la distancia desde el centro puro (0,0) hacia afuera
    float dist_centro = length(uv);
    
    // Interpolamos la opacidad basándonos en la distancia al centro
    float alpha = mix(opacidad_centro, opacidad_borde, clamp(dist_centro, 0.0, 1.0));
    
    // Aplicamos el color original del ColorRect pero con la nueva opacidad calculada
    COLOR = vec4(COLOR.rgb, alpha * COLOR.a);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
