# El proyecto es GDScript puro (sin C#): no hace falta exportar un binario,
# basta con correr el motor de Godot en modo --headless directamente sobre el
# código fuente, igual que en desarrollo y en godot-ci.yml.
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates unzip wget \
    && wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /usr/local/bin \
    && mv "/usr/local/bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip \
    && apt-get purge -y unzip wget \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# Importa los recursos y genera el caché de clases globales (.godot/global_script_
# class_cache.cfg): sin este paso, los scripts que usan `class_name` (MotorDeJuego,
# RoomManager, MensajesRed...) no se resuelven y el servidor no arranca — el mismo
# problema que documenta docs/mapa/cliente.md para GUT headless, pero aquí afecta
# a todo el servidor porque nunca se abrió antes en el editor (ver también
# docs/mapa/servidor-partida.md).
RUN godot --headless --editor --quit --path . || true

EXPOSE 9000/udp

ENTRYPOINT ["godot", "--headless", "--path", ".", "res://server/main_server.tscn"]
