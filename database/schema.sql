-- Schema for Santa Cruz Microbus Routing Database

-- Drop tables if they exist (order is important due to foreign keys)
DROP TABLE IF EXISTS puntos_trasbordos CASCADE;
DROP TABLE IF EXISTS lineas_puntos CASCADE;
DROP TABLE IF EXISTS linea_ruta CASCADE;
DROP TABLE IF EXISTS puntos CASCADE;
DROP TABLE IF EXISTS lineas CASCADE;

-- 1. Lines Table
CREATE TABLE lineas (
    id_linea INTEGER PRIMARY KEY,
    nombre_linea VARCHAR(50) NOT NULL,
    color_linea VARCHAR(10),
    imagen_microbus VARCHAR(255),
    fecha_creacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Geographical Points Table
CREATE TABLE puntos (
    id_point INTEGER PRIMARY KEY, -- matches IdPunto
    latitud DOUBLE PRECISION NOT NULL,
    longitud DOUBLE PRECISION NOT NULL,
    descripcion VARCHAR(255),
    stop VARCHAR(10) NOT NULL DEFAULT 'N' -- 'S' for Stop, 'N' for Normal
);

-- Index for spatial bounding box and point queries
CREATE INDEX idx_puntos_coords ON puntos (latitud, longitud);

-- 3. Line Routes Metadata Table (IdLineaRuta, Description, total Distance/Time)
CREATE TABLE linea_ruta (
    id_linea_ruta INTEGER PRIMARY KEY,
    id_linea INTEGER REFERENCES lineas(id_linea) ON DELETE CASCADE,
    id_ruta INTEGER NOT NULL, -- 1: Salida (outbound), 2: Retorno (inbound)
    descripcion VARCHAR(255),
    distancia DOUBLE PRECISION, -- Total distance in km
    tiempo DOUBLE PRECISION -- Total time in hours
);

-- 4. Route Sequence Segments Table (LineasPuntos)
CREATE TABLE lineas_puntos (
    id_linea_punto INTEGER PRIMARY KEY,
    id_linea_ruta INTEGER REFERENCES linea_ruta(id_linea_ruta) ON DELETE CASCADE,
    id_punto INTEGER REFERENCES puntos(id_point) ON DELETE CASCADE,
    id_punto_dest INTEGER REFERENCES puntos(id_point) ON DELETE SET NULL, -- NULL represents end of route
    orden INTEGER NOT NULL,
    distancia DOUBLE PRECISION NOT NULL DEFAULT 0.0, -- Segment distance in km (calculated & scaled)
    tiempo DOUBLE PRECISION NOT NULL DEFAULT 0.0 -- Segment time in hours (calculated & scaled)
);

CREATE INDEX idx_lineas_puntos_ruta ON lineas_puntos (id_linea_ruta);
CREATE INDEX idx_lineas_puntos_punto ON lineas_puntos (id_punto);

-- 5. Transfers Table (PuntosTrasbordos)
CREATE TABLE puntos_trasbordos (
    id_trasbordo INTEGER PRIMARY KEY,
    id_punto INTEGER REFERENCES puntos(id_point) ON DELETE CASCADE,
    id_linea_origen INTEGER REFERENCES linea_ruta(id_linea_ruta) ON DELETE CASCADE,
    id_linea_destino INTEGER REFERENCES linea_ruta(id_linea_ruta) ON DELETE CASCADE,
    penalizacion_min DOUBLE PRECISION NOT NULL DEFAULT 5.0
);

CREATE INDEX idx_trasbordos_punto ON puntos_trasbordos (id_punto);
