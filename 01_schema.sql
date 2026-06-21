-- ============================================================
--  PROYECTO SQL: PLATAFORMA DE STREAMING DE MÚSICA
--  Archivo: 01_schema.sql
--  Autor:   Aroa Barberán Martín
--  Desc:    Creación del modelo dimensional completo:
--           1 tabla de hechos + 5 dimensiones
--           Incluye PKs, FKs, constraints, índices,
--           vistas de negocio y función auxiliar.
-- ============================================================

-- Ejecutar siempre desde cero sin errores
DROP DATABASE IF EXISTS streaming_db;
CREATE DATABASE streaming_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE streaming_db;


-- ============================================================
-- 1. DIMENSIÓN: DIM_ARTISTAS
-- Granularidad: 1 fila = 1 artista único.
-- PK: id_artista (INT AUTO_INCREMENT) — clave subrogada,
--     independiente del nombre para permitir renombres.
-- ============================================================
CREATE TABLE dim_artistas (
    id_artista       INT            NOT NULL AUTO_INCREMENT,
    nombre_artista   VARCHAR(150)   NOT NULL,
    pais_origen      VARCHAR(100)   NOT NULL DEFAULT 'Desconocido',
    genero_principal VARCHAR(80)    NOT NULL,
    anio_debut       YEAR           NOT NULL,

    -- CHECK: el debut no puede ser antes de 1900 ni en el futuro
    CONSTRAINT chk_debut CHECK (anio_debut BETWEEN 1900 AND 2025),

    PRIMARY KEY (id_artista)
);


-- ============================================================
-- 2. DIMENSIÓN: DIM_ALBUMES
-- Granularidad: 1 fila = 1 álbum publicado por un artista.
-- FK: id_artista → dim_artistas (un álbum tiene un único autor).
-- tipo: ENUM para garantizar valores controlados.
-- ============================================================
CREATE TABLE dim_albumes (
    id_album          INT           NOT NULL AUTO_INCREMENT,
    id_artista        INT           NOT NULL,
    titulo_album      VARCHAR(200)  NOT NULL,
    fecha_lanzamiento DATE          NOT NULL,
    tipo              ENUM('Album','EP','Single','Recopilatorio') NOT NULL DEFAULT 'Album',
    num_canciones     TINYINT       NOT NULL DEFAULT 1,

    -- CHECK: un álbum tiene entre 1 y 30 canciones
    CONSTRAINT chk_num_canciones CHECK (num_canciones BETWEEN 1 AND 30),

    PRIMARY KEY (id_album),
    CONSTRAINT fk_album_artista FOREIGN KEY (id_artista)
        REFERENCES dim_artistas(id_artista)
        ON DELETE RESTRICT   -- no borrar artista si tiene álbumes
        ON UPDATE CASCADE
);


-- ============================================================
-- 3. DIMENSIÓN: DIM_CANCIONES
-- Granularidad: 1 fila = 1 canción única.
-- FK doble: id_album (pertenece a un álbum)
--           id_artista (desnormalización deliberada para
--           facilitar queries directas sin pasar por álbum).
-- Justificación: en un modelo dimensional es aceptable esta
-- redundancia controlada para mejorar rendimiento analítico.
-- ============================================================
CREATE TABLE dim_canciones (
    id_cancion        INT           NOT NULL AUTO_INCREMENT,
    id_album          INT           NOT NULL,
    id_artista        INT           NOT NULL,
    titulo            VARCHAR(200)  NOT NULL,
    genero            VARCHAR(80)   NOT NULL,
    duracion_seg      SMALLINT      NOT NULL,
    fecha_lanzamiento DATE          NOT NULL,
    bpm               SMALLINT      NOT NULL DEFAULT 120,

    -- CHECK: duración entre 15 segundos y 60 minutos
    CONSTRAINT chk_duracion CHECK (duracion_seg BETWEEN 15 AND 3600),
    -- CHECK: BPM realista entre 40 y 300
    CONSTRAINT chk_bpm CHECK (bpm BETWEEN 40 AND 300),

    PRIMARY KEY (id_cancion),
    CONSTRAINT fk_cancion_album   FOREIGN KEY (id_album)
        REFERENCES dim_albumes(id_album)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_cancion_artista FOREIGN KEY (id_artista)
        REFERENCES dim_artistas(id_artista)
        ON DELETE RESTRICT ON UPDATE CASCADE
);


-- ============================================================
-- 4. DIMENSIÓN: DIM_USUARIOS
-- Granularidad: 1 fila = 1 cuenta de usuario.
-- email: UNIQUE — no pueden existir dos cuentas con el mismo.
-- plan: ENUM para evitar valores libres en columna crítica.
-- edad: CHECK para evitar outliers (negativo o >120).
-- ============================================================
CREATE TABLE dim_usuarios (
    id_usuario      INT           NOT NULL AUTO_INCREMENT,
    nombre          VARCHAR(150)  NOT NULL,
    email           VARCHAR(255)  NOT NULL,
    plan            ENUM('Free','Premium','Familiar','Estudiante') NOT NULL DEFAULT 'Free',
    fecha_registro  DATE          NOT NULL,
    pais            VARCHAR(100)  NOT NULL DEFAULT 'España',
    edad            TINYINT       NOT NULL,

    -- CHECK: edades válidas entre 13 (mínimo legal) y 120
    CONSTRAINT chk_edad CHECK (edad BETWEEN 13 AND 120),

    PRIMARY KEY (id_usuario),
    CONSTRAINT uq_email UNIQUE (email)  -- email único por usuario
);


-- ============================================================
-- 5. DIMENSIÓN: DIM_FECHA
-- Granularidad: 1 fila = 1 día del calendario.
-- Tabla de calendario precalculada: evita calcular funciones
-- de fecha en cada consulta analítica (mejora rendimiento).
-- PK: id_fecha como INT en formato YYYYMMDD — patrón estándar
--     en DWH que permite joins directos sin lookup adicional.
-- ============================================================
CREATE TABLE dim_fecha (
    id_fecha       INT          NOT NULL,  -- formato: 20240315
    fecha          DATE         NOT NULL,
    anio           SMALLINT     NOT NULL,
    mes            TINYINT      NOT NULL,
    dia            TINYINT      NOT NULL,
    nombre_dia     VARCHAR(20)  NOT NULL,  -- 'Lunes', 'Martes'...
    nombre_mes     VARCHAR(20)  NOT NULL,  -- 'Enero', 'Febrero'...
    trimestre      TINYINT      NOT NULL,
    es_fin_semana  TINYINT      NOT NULL DEFAULT 0,  -- 0=No, 1=Sí

    CONSTRAINT chk_mes        CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT chk_dia        CHECK (dia BETWEEN 1 AND 31),
    CONSTRAINT chk_trimestre  CHECK (trimestre BETWEEN 1 AND 4),
    CONSTRAINT chk_fds        CHECK (es_fin_semana IN (0, 1)),

    PRIMARY KEY (id_fecha),
    CONSTRAINT uq_fecha UNIQUE (fecha)
);


-- ============================================================
-- 6. TABLA DE HECHOS: FACT_REPRODUCCIONES
-- Granularidad: 1 fila = 1 evento de reproducción.
-- Es el centro del modelo estrella. Todas las FK apuntan
-- a las dimensiones. duracion_escuchada permite calcular
-- tasa de completado (KPI clave en plataformas de streaming).
-- ============================================================
CREATE TABLE fact_reproducciones (
    id_reproduccion     INT            NOT NULL AUTO_INCREMENT,
    id_usuario          INT            NOT NULL,
    id_cancion          INT            NOT NULL,
    id_fecha            INT            NOT NULL,
    id_album            INT            NOT NULL,
    duracion_escuchada  DECIMAL(6,2)   NOT NULL DEFAULT 0.00,
    completada          TINYINT        NOT NULL DEFAULT 0,  -- 0=No, 1=Sí
    timestamp_inicio    DATETIME       NOT NULL,

    -- CHECK: no se puede escuchar tiempo negativo
    CONSTRAINT chk_duracion_esc CHECK (duracion_escuchada >= 0),
    CONSTRAINT chk_completada   CHECK (completada IN (0, 1)),

    PRIMARY KEY (id_reproduccion),
    CONSTRAINT fk_repr_usuario  FOREIGN KEY (id_usuario)
        REFERENCES dim_usuarios(id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_repr_cancion  FOREIGN KEY (id_cancion)
        REFERENCES dim_canciones(id_cancion)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_repr_fecha    FOREIGN KEY (id_fecha)
        REFERENCES dim_fecha(id_fecha)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_repr_album    FOREIGN KEY (id_album)
        REFERENCES dim_albumes(id_album)
        ON DELETE RESTRICT ON UPDATE CASCADE
);


-- ============================================================
-- ÍNDICES
-- Los índices se crean sobre columnas usadas frecuentemente
-- en WHERE, JOIN y GROUP BY para mejorar rendimiento.
-- ============================================================

-- Índice en fact_reproducciones(id_usuario):
-- Las consultas más frecuentes filtran por usuario
-- (historial, segmentación por plan). Sin índice, MySQL
-- haría full scan de toda la fact table en cada query.
CREATE INDEX idx_repr_usuario  ON fact_reproducciones(id_usuario);

-- Índice en fact_reproducciones(id_cancion):
-- Para rankings de canciones más reproducidas (GROUP BY id_cancion)
CREATE INDEX idx_repr_cancion  ON fact_reproducciones(id_cancion);

-- Índice en fact_reproducciones(id_fecha):
-- Análisis temporales (tendencias por mes, día de semana)
CREATE INDEX idx_repr_fecha    ON fact_reproducciones(id_fecha);

-- Índice en dim_canciones(genero):
-- Segmentaciones por género son habituales en el EDA
CREATE INDEX idx_cancion_genero ON dim_canciones(genero);

-- Índice en dim_usuarios(plan):
-- Comparativas Free vs Premium son el KPI más repetido
CREATE INDEX idx_usuario_plan  ON dim_usuarios(plan);


-- ============================================================
-- FUNCIÓN: fn_duracion_formato
-- Convierte segundos a formato legible 'Xm Ys'.
-- Justificación: reutilizable en vistas y consultas,
-- evita repetir la misma lógica CAST/MOD en cada query.
-- MySQL requiere cambiar el delimitador para definir funciones.
-- ============================================================
DELIMITER $$

CREATE FUNCTION fn_duracion_formato(segundos INT)
RETURNS VARCHAR(20)
DETERMINISTIC
BEGIN
    DECLARE minutos INT;
    DECLARE segs    INT;
    SET minutos = FLOOR(segundos / 60);
    SET segs    = segundos MOD 60;
    RETURN CONCAT(minutos, 'm ', segs, 's');
END$$

DELIMITER ;


-- ============================================================
-- VISTA 1: vw_reproducciones_completas
-- Vista de negocio que une fact + dimensiones principales.
-- Propósito: punto de entrada estándar para análisis.
-- Evita repetir los JOINs en cada consulta del EDA.
-- ============================================================
CREATE OR REPLACE VIEW vw_reproducciones_completas AS
SELECT
    fr.id_reproduccion,
    fr.timestamp_inicio,
    fr.duracion_escuchada,
    fr.completada,

    -- Dimensión usuario
    u.id_usuario,
    u.nombre          AS nombre_usuario,
    u.plan            AS plan_usuario,
    u.pais            AS pais_usuario,
    u.edad            AS edad_usuario,

    -- Dimensión canción
    c.id_cancion,
    c.titulo          AS titulo_cancion,
    c.genero,
    c.duracion_seg,
    fn_duracion_formato(c.duracion_seg) AS duracion_formato,

    -- Dimensión artista
    a.id_artista,
    a.nombre_artista,
    a.pais_origen     AS pais_artista,

    -- Dimensión álbum
    al.id_album,
    al.titulo_album,
    al.tipo           AS tipo_album,

    -- Dimensión fecha
    f.fecha,
    f.anio,
    f.mes,
    f.nombre_mes,
    f.nombre_dia,
    f.trimestre,
    f.es_fin_semana

FROM fact_reproducciones fr
INNER JOIN dim_usuarios   u  ON fr.id_usuario = u.id_usuario
INNER JOIN dim_canciones  c  ON fr.id_cancion = c.id_cancion
INNER JOIN dim_artistas   a  ON c.id_artista  = a.id_artista
INNER JOIN dim_albumes    al ON fr.id_album   = al.id_album
INNER JOIN dim_fecha      f  ON fr.id_fecha   = f.id_fecha;


-- ============================================================
-- VISTA 2: vw_resumen_artistas
-- KPIs agregados por artista: reproducciones totales,
-- Canciones únicas escuchadas, tasa de completado media.
-- Propósito: dashboard ejecutivo / ranking de artistas.
-- ============================================================
CREATE OR REPLACE VIEW vw_resumen_artistas AS
SELECT
    a.id_artista,
    a.nombre_artista,
    a.genero_principal,
    a.pais_origen,
    COUNT(fr.id_reproduccion)            AS total_reproducciones,
    COUNT(DISTINCT fr.id_cancion)        AS canciones_unicas_escuchadas,
    ROUND(AVG(fr.duracion_escuchada), 2) AS avg_duracion_escuchada_seg,
    ROUND(AVG(fr.completada) * 100, 1)   AS pct_completado,
    COUNT(DISTINCT fr.id_usuario)        AS oyentes_unicos
FROM dim_artistas a
LEFT JOIN dim_canciones c
    ON a.id_artista = c.id_artista
LEFT JOIN fact_reproducciones fr
    ON c.id_cancion = fr.id_cancion
GROUP BY
    a.id_artista,
    a.nombre_artista,
    a.genero_principal,
    a.pais_origen;