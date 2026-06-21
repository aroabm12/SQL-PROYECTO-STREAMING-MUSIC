-- ============================================================
--  PROYECTO SQL: PLATAFORMA DE STREAMING DE MÚSICA
--  Archivo: 03_eda.sql
--  Desc:    Análisis Exploratorio de Datos (EDA) completo.
--           Incluye: limpieza, validación, análisis descriptivo
--           y consultas analíticas de negocio.
-- ============================================================

USE streaming_db;


-- ============================================================
-- BLOQUE 1: CALIDAD DE DATOS — VALIDACIÓN Y LIMPIEZA
-- ============================================================

-- ------------------------------------------------------------
-- 1.1 Detectar valores NULL en tablas críticas
-- Insight: identifica huecos en los datos antes de analizar.
-- ------------------------------------------------------------
SELECT 'dim_usuarios' AS tabla,
       SUM(CASE WHEN nombre         IS NULL THEN 1 ELSE 0 END) AS nulls_nombre,
       SUM(CASE WHEN email           IS NULL THEN 1 ELSE 0 END) AS nulls_email,
       SUM(CASE WHEN plan            IS NULL THEN 1 ELSE 0 END) AS nulls_plan,
       SUM(CASE WHEN pais            IS NULL THEN 1 ELSE 0 END) AS nulls_pais,
       SUM(CASE WHEN edad            IS NULL THEN 1 ELSE 0 END) AS nulls_edad
FROM dim_usuarios;

SELECT 'dim_canciones' AS tabla,
       SUM(CASE WHEN titulo          IS NULL THEN 1 ELSE 0 END) AS nulls_titulo,
       SUM(CASE WHEN genero          IS NULL THEN 1 ELSE 0 END) AS nulls_genero,
       SUM(CASE WHEN duracion_seg    IS NULL THEN 1 ELSE 0 END) AS nulls_duracion,
       SUM(CASE WHEN bpm             IS NULL THEN 1 ELSE 0 END) AS nulls_bpm
FROM dim_canciones;

SELECT 'fact_reproducciones' AS tabla,
       SUM(CASE WHEN duracion_escuchada IS NULL THEN 1 ELSE 0 END) AS nulls_duracion,
       SUM(CASE WHEN completada         IS NULL THEN 1 ELSE 0 END) AS nulls_completada,
       SUM(CASE WHEN timestamp_inicio   IS NULL THEN 1 ELSE 0 END) AS nulls_timestamp
FROM fact_reproducciones;


-- ------------------------------------------------------------
-- 1.2 Corregir NULLs en pais_origen de artistas
-- Si un artista no tiene país, lo marcamos como 'Desconocido'.
-- ------------------------------------------------------------
UPDATE dim_artistas
SET pais_origen = 'Desconocido'
WHERE pais_origen IS NULL;


-- ------------------------------------------------------------
-- 1.3 Detectar emails duplicados en dim_usuarios
-- Un email duplicado indica cuentas duplicadas — lo cual genera un problema
-- ------------------------------------------------------------
SELECT email,
       COUNT(*) AS veces_repetido
FROM dim_usuarios
GROUP BY email
HAVING COUNT(*) > 1
ORDER BY veces_repetido DESC;


-- ------------------------------------------------------------
-- 1.4 Detectar canciones duplicadas (mismo título y artista)
-- Usando RANK() PARTITION BY para identificar duplicados.
-- ------------------------------------------------------------
SELECT titulo, id_artista, COUNT(*) AS duplicados
FROM dim_canciones
GROUP BY titulo, id_artista
HAVING COUNT(*) > 1;

-- Versión con RANK para ver cuál conservar:
SELECT *
FROM (
    SELECT id_cancion, titulo, id_artista,
           RANK() OVER (PARTITION BY titulo, id_artista ORDER BY id_cancion) AS rk
    FROM dim_canciones
) ranked
WHERE rk > 1;


-- ------------------------------------------------------------
-- 1.5 Detectar outliers — edades fuera de rango
-- Edades < 13 (mínimo legal) o > 100 son datos erróneos.
-- ------------------------------------------------------------
SELECT id_usuario, nombre, edad
FROM dim_usuarios
WHERE edad < 13 OR edad > 100;


-- ------------------------------------------------------------
-- 1.6 Detectar reproducciones con duración mayor que la canción
-- Outlier de negocio: no puedes escuchar más de lo que dura.
-- ------------------------------------------------------------
SELECT fr.id_reproduccion,
       c.titulo,
       c.duracion_seg                          AS duracion_cancion,
       fr.duracion_escuchada                   AS duracion_escuchada,
       fr.duracion_escuchada - c.duracion_seg  AS diferencia
FROM fact_reproducciones fr
INNER JOIN dim_canciones c ON fr.id_cancion = c.id_cancion
WHERE fr.duracion_escuchada > c.duracion_seg;


-- ------------------------------------------------------------
-- 1.7 Verificar coherencia de fechas
-- CAST: conversión explícita de id_fecha (INT) a DATE
-- para que las fechas almacenadas como número entero en id_fecha son coherentes con la columna fecha.
-- ------------------------------------------------------------
SELECT id_fecha,
       fecha,
       -- Reconstruimos la fecha desde el INT y comparamos
       STR_TO_DATE(CAST(id_fecha AS CHAR), '%Y%m%d') AS fecha_reconstruida,
       CASE
           WHEN fecha = STR_TO_DATE(CAST(id_fecha AS CHAR), '%Y%m%d')
           THEN 'OK'
           ELSE 'ERROR — fechas no coinciden'
       END AS validacion
FROM dim_fecha
LIMIT 10;


-- ------------------------------------------------------------
-- 1.8 Detectar canciones con BPM fuera de rango realista
-- BPM < 40 o > 300 no existe en música comercial.
-- ------------------------------------------------------------
SELECT id_cancion, titulo, bpm
FROM dim_canciones
WHERE bpm < 40 OR bpm > 300;


-- ============================================================
-- BLOQUE 2: EDA — ANÁLISIS DESCRIPTIVO GENERAL
-- ============================================================

-- ------------------------------------------------------------
-- 2.1 Resumen general del volumen de datos
-- Insight: visión rápida del tamaño del dataset.
-- ------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM dim_artistas)        AS total_artistas,
    (SELECT COUNT(*) FROM dim_albumes)         AS total_albumes,
    (SELECT COUNT(*) FROM dim_canciones)       AS total_canciones,
    (SELECT COUNT(*) FROM dim_usuarios)        AS total_usuarios,
    (SELECT COUNT(*) FROM fact_reproducciones) AS total_reproducciones,
    (SELECT COUNT(*) FROM dim_fecha)           AS dias_en_calendario;


-- ------------------------------------------------------------
-- 2.2 Distribución de usuarios por plan
-- Insight: qué porcentaje son Free vs de pago.
-- Crítico para evaluar la tasa de conversión.
-- ------------------------------------------------------------
SELECT
    plan,
    COUNT(*) AS total_usuarios,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS porcentaje_del_total
FROM dim_usuarios
GROUP BY plan
ORDER BY total_usuarios DESC;


-- ------------------------------------------------------------
-- 2.3 Distribución de usuarios por país
-- Insight: qué mercados tienen más usuarios activos.
-- ------------------------------------------------------------
SELECT
    pais,
    COUNT(*) AS total_usuarios
FROM dim_usuarios
GROUP BY pais
ORDER BY total_usuarios DESC;


-- ------------------------------------------------------------
-- 2.4 Estadísticas descriptivas de edad de usuarios
-- Insight: perfil demográfico de la base de usuarios.
-- ------------------------------------------------------------
SELECT
    MIN(edad)                       AS edad_minima,
    MAX(edad)                       AS edad_maxima,
    ROUND(AVG(edad), 1)             AS edad_media,
    COUNT(CASE WHEN edad < 25 THEN 1 END) AS usuarios_menores_25,
    COUNT(CASE WHEN edad BETWEEN 25 AND 40 THEN 1 END) AS usuarios_entre_25_40,
    COUNT(CASE WHEN edad > 40 THEN 1 END) AS usuarios_mayores_40
FROM dim_usuarios;


-- ------------------------------------------------------------
-- 2.5 Distribución de canciones por género
-- Insight: qué géneros dominan el catálogo.
-- ------------------------------------------------------------
SELECT
    genero,
    COUNT(*)                        AS total_canciones,
    ROUND(AVG(duracion_seg), 0)     AS duracion_media_seg,
    ROUND(AVG(bpm), 0)              AS bpm_medio,
    MIN(duracion_seg)               AS cancion_mas_corta,
    MAX(duracion_seg)               AS cancion_mas_larga
FROM dim_canciones
GROUP BY genero
ORDER BY total_canciones DESC;


-- ------------------------------------------------------------
-- 2.6 Estadísticas de reproducciones
-- Insight: volumen de actividad y canciones que los usuarios escuchan hasta el final.
-- ------------------------------------------------------------
SELECT
    COUNT(*)                                    AS total_reproducciones,
    SUM(completada)                             AS reproducciones_completas,
    ROUND(AVG(completada) * 100, 1)             AS porcentaje_completado_global,
    ROUND(AVG(duracion_escuchada), 1)           AS avg_seg_escuchados,
    MIN(timestamp_inicio)                       AS primera_reproduccion,
    MAX(timestamp_inicio)                       AS ultima_reproduccion
FROM fact_reproducciones;


-- ============================================================
-- BLOQUE 3: CONSULTAS ANALÍTICAS DE NEGOCIO
-- ============================================================

-- ------------------------------------------------------------
-- CONSULTA 1: Top 10 canciones más reproducidas
-- Insight: identifica los hits de la plataforma.
-- Los artistas con más canciones en el top tienen mayor
-- engagement — dato clave para negociar royalties.
-- ------------------------------------------------------------
SELECT
    c.titulo                            AS cancion,
    a.nombre_artista                    AS artista,
    c.genero,
    COUNT(fr.id_reproduccion)           AS total_reproducciones,
    ROUND(AVG(fr.completada) * 100, 1) AS porcentaje_completado
FROM fact_reproducciones fr
INNER JOIN dim_canciones c  ON fr.id_cancion = c.id_cancion
INNER JOIN dim_artistas  a  ON c.id_artista  = a.id_artista
GROUP BY c.id_cancion, c.titulo, a.nombre_artista, c.genero
ORDER BY total_reproducciones DESC
LIMIT 10;

-- CONCLUSIÓN:
-- Blinding Lights de The Weeknd lidera con 12 reproducciones y 100% de completado,
-- siendo la canción más escuchada Y la que más engancha de la plataforma.
-- Anti-Hero y Happier Than Ever tienen solo un 55.6% de completado pese a estar
-- en el top — sus usuarios las abandonan a mitad, lo que sugiere que
-- se reproducen por algoritmo pero no generan engagement real.




-- ------------------------------------------------------------
-- CONSULTA 2: Reproducciones por mes — tendencia anual
-- Insight: detecta estacionalidad en el consumo de música.
-- Meses con más reproducciones → mayor demanda de servidores
-- y oportunidades para campañas de marketing.
-- ------------------------------------------------------------
SELECT
    f.anio,
    f.mes,
    f.nombre_mes,
    COUNT(fr.id_reproduccion)           AS total_reproducciones,
    SUM(fr.completada)                  AS reproducciones_completas,
    ROUND(AVG(fr.completada) * 100, 1) AS porcentaje_completado
FROM fact_reproducciones fr
INNER JOIN dim_fecha f ON fr.id_fecha = f.id_fecha
GROUP BY f.anio, f.mes, f.nombre_mes
ORDER BY f.anio, f.mes;

-- CONCLUSIÓN CONSULTA 2:
-- Hay dos picos claros de actividad: Enero y Febrero con 20 reproducciones cada mes
-- y Diciembre (31 reproducciones siendo el mes más alto del año).
-- El pico de Diciembre se explica por las vacaciones navideñas:
-- la gente tiene más tiempo libre y consume más música.
-- De Marzo a Noviembre se estabiliza en 10-15 reproducciones mensuales.
-- El porcentaje de completado mejora a lo largo del año: empieza en 70%
-- en Enero y llega al 96.8% en Diciembre — los usuarios más fieles
-- permanecen en la plataforma y escuchan canciones enteras.
-- La recomendación sería concentrar lanzamientos de nuevos álbumes y campañas
-- de marketing en Enero y Diciembre para aprovechar los picos de audiencia.




-- ------------------------------------------------------------
-- CONSULTA 3: Comparativa Free vs Premium
-- Insight: los usuarios Premium escuchan más y completan
-- más canciones → justifica el modelo freemium.
-- ------------------------------------------------------------
SELECT
    u.plan,
    COUNT(DISTINCT fr.id_usuario)               AS usuarios_activos,
    COUNT(fr.id_reproduccion)                   AS total_reproducciones,
    ROUND(COUNT(fr.id_reproduccion) /
          COUNT(DISTINCT fr.id_usuario), 1)     AS reproducciones_por_usuario,
    ROUND(AVG(fr.completada) * 100, 1)          AS porcentaje_completado,
    ROUND(AVG(fr.duracion_escuchada), 1)        AS avg_seg_escuchados
FROM fact_reproducciones fr
INNER JOIN dim_usuarios u ON fr.id_usuario = u.id_usuario
GROUP BY u.plan
ORDER BY reproducciones_por_usuario DESC;

-- CONCLUSIÓN:
-- Premium lidera en reproducciones totales (66) y reproducciones por usuario (6.0),
-- confirmando que los usuarios de pago son más activos.
-- Sin embargo hay un dato sorprendente: los usuarios Free tienen mayor
-- porcentaje de completado (86.5%) que los Premium (81.8%), y los Estudiante
-- son los que más completan canciones (93.1%) con 211.6 segundos de media.
-- Esto sugiere que los usuarios Free y Estudiante escuchan con más atención
-- posiblemente porque tienen límite de saltos y aprovechan cada reproducción.
-- Los Premium en cambio saltan canciones con más libertad al no tener restricciones,
-- lo que baja su tasa de completado pero sube su volumen total.
-- Recomendación: campañas de conversión dirigidas a usuarios Free activos
-- (9 usuarios generan 52 reproducciones) tienen alto potencial de retorno.




-- ------------------------------------------------------------
-- CONSULTA 4: Top artistas por oyentes únicos
-- Insight: diferencia entre reproducciones totales y alcance
-- real. Un artista con muchos oyentes únicos tiene mayor
-- impacto cultural aunque tenga menos reproducciones totales.
-- ------------------------------------------------------------
SELECT
    a.nombre_artista,
    a.genero_principal,
    a.pais_origen,
    COUNT(fr.id_reproduccion)           AS total_reproducciones,
    COUNT(DISTINCT fr.id_usuario)       AS oyentes_unicos,
    ROUND(AVG(fr.completada) * 100, 1) AS porcentaje_completado
FROM dim_artistas a
LEFT JOIN dim_canciones c      ON a.id_artista  = c.id_artista
LEFT JOIN fact_reproducciones fr ON c.id_cancion = fr.id_cancion
GROUP BY a.id_artista, a.nombre_artista, a.genero_principal, a.pais_origen
ORDER BY oyentes_unicos DESC
LIMIT 10;

-- CONCLUSIÓN CONSULTA 4:
-- The Weeknd lidera en reproducciones totales (14) con 100% de completado,
-- siendo el artista que más engancha de toda la plataforma.
-- Bad Bunny, Taylor Swift, Karol G y Billie Eilish empatan en oyentes únicos (9)
-- con 10 reproducciones cada uno los que demuestran el mayor alcance cultural
-- aunque no sean los más reproducidos en total.
-- Hay una diferencia clave entre volumen y calidad:
-- Taylor Swift y Billie Eilish tienen solo 60% de completado pese a su alcance,
-- mientras que J Balvin, Coldplay y Dua Lipa tienen 100% con menos oyentes.
-- Esto significa que The Weeknd, J Balvin y Coldplay son candidatos ideales
-- para exclusividades o contenido patrocinado — sus oyentes son más fieles.



-- ------------------------------------------------------------
-- CONSULTA 5: Géneros más escuchados por plan de usuario
-- Insight: los usuarios Free y Premium consumen géneros
-- distintos → permite personalizar la oferta por segmento
-- y diseñar playlists editoriales diferenciadas.
-- ------------------------------------------------------------
SELECT
    u.plan,
    c.genero,
    COUNT(fr.id_reproduccion)           AS reproducciones,
    ROUND(AVG(fr.completada) * 100, 1) AS porcentaje_completado
FROM fact_reproducciones fr
INNER JOIN dim_usuarios  u ON fr.id_usuario = u.id_usuario
INNER JOIN dim_canciones c ON fr.id_cancion = c.id_cancion
GROUP BY u.plan, c.genero
ORDER BY u.plan, reproducciones DESC;

-- CONCLUSIÓN:
-- El Reggaeton es el género número 1 en todos los planes excepto Familiar,
-- donde el Pop lidera (10 reproducciones). Esto sugiere que las familias
-- tienen un perfil de consumo más mainstream y menos urbano.
-- Los usuarios Free escuchan Reggaeton con mayor fidelidad (93.3% completado)
-- que los Premium (76.2%) — refuerza el hallazgo de la Consulta 3:
-- los Free aprovechan más cada reproducción al tener límite de saltos.
-- Dato llamativo: Urban tiene solo 33.3% de completado en Premium,
-- el más bajo de toda la tabla lo que significa que los usuarios Premium abandonan
-- este género rápidamente, posible señal de que no encaja con su perfil.
-- El R&B tiene 100% de completado en Free, Premium, Familiar y Estudiante
-- — es el género más fiel transversalmente aunque no sea el más escuchado.
-- Recomendación: crear playlists diferenciadas por plan:
-- Reggaeton para Free y Premium, Pop para Familiar,
-- y revisar el catálogo Urban ya que genera alto abandono en Premium.


-- ------------------------------------------------------------
-- CONSULTA 6: Análisis de fin de semana vs días laborables
-- Insight: si el consumo sube en fin de semana → programar contenido
-- nuevo los viernes para aprovechar el pico de audiencia.
-- ------------------------------------------------------------
SELECT
    CASE WHEN f.es_fin_semana = 1 THEN 'Fin de semana'
         ELSE 'Día laborable' END          AS tipo_dia,
    COUNT(fr.id_reproduccion)              AS total_reproducciones,
    ROUND(AVG(fr.completada) * 100, 1)    AS porcentaje_completado,
    COUNT(DISTINCT fr.id_usuario)          AS usuarios_unicos
FROM fact_reproducciones fr
INNER JOIN dim_fecha f ON fr.id_fecha = f.id_fecha
GROUP BY f.es_fin_semana
ORDER BY total_reproducciones DESC;

-- CONCLUSIÓN:
-- Los días laborables generan más del doble de reproducciones (125) 
-- que los fines de semana (51), lo cual va contra la intuición inicial
-- de que la gente escucha más música cuando tiene tiempo libre.
-- Esto sugiere que los usuarios escuchan música principalmente mientras
-- trabajan, estudian o se desplazan — uso de la plataforma como
-- "música de fondo" durante la semana laboral.
-- El porcentaje de completado es prácticamente igual en ambos casos
-- (84.8% laborable vs 84.3% finde) — el tipo de día no afecta
-- a la calidad de la escucha.
-- Los 30 usuarios únicos en ambos casos indica que los mismos usuarios
-- escuchan tanto entre semana como en fin de semana, no hay segmentos distintos.
-- Recomendación: orientar las campañas de notificaciones push y 
-- lanzamientos de contenido a días laborables, especialmente 
-- lunes y miércoles que suelen ser los picos de consumo en semana.


-- ------------------------------------------------------------
-- CONSULTA 7: Ranking de canciones por tasa de completado
-- con CTEs encadenadas
-- Insight: canciones con alta tasa de completado son las que
-- más enganchan → candidatas para playlists editoriales.
-- ------------------------------------------------------------
WITH cte_stats AS (
    -- CTE 1: estadísticas base por canción
    SELECT
        fr.id_cancion,
        COUNT(*)                            AS total_reproducciones,
        SUM(fr.completada)                  AS veces_completada,
        ROUND(AVG(fr.completada) * 100, 1) AS porcentaje_completado,
        ROUND(AVG(fr.duracion_escuchada), 1) AS avg_seg_escuchados
    FROM fact_reproducciones fr
    GROUP BY fr.id_cancion
    HAVING COUNT(*) >= 2  -- solo canciones con mínimo 2 reproducciones
),
cte_ranking AS (
    -- CTE 2: añadimos info de canción y artista + ranking por género
    SELECT
        s.id_cancion,
        c.titulo,
        c.genero,
        a.nombre_artista,
        s.total_reproducciones,
        s.porcentaje_completado,
        s.avg_seg_escuchados,
        fn_duracion_formato(c.duracion_seg) AS duracion_total,
        RANK() OVER (
            PARTITION BY c.genero
            ORDER BY s.porcentaje_completado DESC
        ) AS ranking_en_genero
    FROM cte_stats s
    INNER JOIN dim_canciones c ON s.id_cancion = c.id_cancion
    INNER JOIN dim_artistas  a ON c.id_artista  = a.id_artista
)
-- Resultado final: top 1 por género
SELECT *
FROM cte_ranking
WHERE ranking_en_genero = 1
ORDER BY porcentaje_completado DESC;

-- CONCLUSIÓN:
-- Esta consulta muestra la canción número 1 en completado dentro de cada género.
-- Pop, R&B y Reggaeton tienen múltiples canciones con 100% de completado,
-- lo que confirma que son los géneros con mayor engagement de la plataforma.
-- Dato destacable: Champagne Poetry de Drake (Hip-Hop) dura 5m 37s —
-- la canción más larga del ranking — y aun así tiene 87.5% de completado,
-- lo que demuestra que la duración no es un freno si la canción engancha.
-- En el extremo opuesto, Malamente de Rosalía (Pop Flamenco) tiene solo
-- 66.7% de completado — el más bajo del ranking — sugiriendo que
-- el Pop Flamenco es un género de nicho que no conecta con la mayoría.
-- C. Tangana (Urban) con 71.4% también muestra bajo engagement,
-- consistente con lo visto en la Consulta 5 donde Urban tenía
-- el peor completado entre los Premium.
-- Recomendación: incluir Levitating, Blinding Lights y Tití Me Preguntó
-- en todas las playlists editoriales — son los líderes absolutos
-- de engagement en sus géneros respectivos.




-- ------------------------------------------------------------
-- CONSULTA 8: Usuarios más activos con su género favorito
-- Insight: identifica power users — base para programas
-- de fidelización y embajadores de marca.
-- ------------------------------------------------------------
WITH cte_actividad AS (
    -- CTE 1: reproducciones totales por usuario
    SELECT
        fr.id_usuario,
        COUNT(*)                            AS total_reproducciones,
        ROUND(AVG(fr.completada) * 100, 1) AS porcentaje_completado,
        ROUND(AVG(fr.duracion_escuchada), 1) AS avg_escuchado_seg
    FROM fact_reproducciones fr
    GROUP BY fr.id_usuario
),
cte_genero_favorito AS (
    -- CTE 2: género más escuchado por usuario
    SELECT id_usuario, genero
    FROM (
        SELECT
            fr.id_usuario,
            c.genero,
            COUNT(*) AS cnt,
            RANK() OVER (PARTITION BY fr.id_usuario ORDER BY COUNT(*) DESC) AS rk
        FROM fact_reproducciones fr
        INNER JOIN dim_canciones c ON fr.id_cancion = c.id_cancion
        GROUP BY fr.id_usuario, c.genero
    ) ranked
    WHERE rk = 1
)
SELECT
    u.nombre,
    u.plan,
    u.pais,
    u.edad,
    a.total_reproducciones,
    a.porcentaje_completado,
    fn_duracion_formato(CAST(a.avg_escuchado_seg AS UNSIGNED)) AS avg_escuchado,
    g.genero                                    AS genero_favorito
FROM cte_actividad a
INNER JOIN dim_usuarios        u ON a.id_usuario = u.id_usuario
INNER JOIN cte_genero_favorito g ON a.id_usuario = g.id_usuario
ORDER BY a.total_reproducciones DESC
LIMIT 10;

-- CONCLUSIÓN:
-- Carlos Martínez es el usuario más destacado
-- con 7 reproducciones y 100% de completado, escucha R&B y siempre
-- termina las canciones.
-- Laura Sánchez también tiene 7 reproducciones pero solo 57.1% de completado,
-- es activa pero abandona canciones, perfil típico de
-- usuario que necesita mejores recomendaciones personalizadas.
-- Algunos usuarios aparecen con dos géneros favoritos (Sofía, Pablo, Ana)
-- lo que indica empate en reproducciones entre géneros — son usuarios
-- con gustos amplios, candidatos ideales para playlists mixtas.
-- El top de usuarios activos mezcla todos los planes: Premium, Free,
-- Estudiante y Familiar — la actividad no depende del plan sino
-- del perfil personal del usuario.
-- Recomendación: contactar con los oyentes mas comprometidos para 
-- ofrecer descuentos en renovación anual.



-- ------------------------------------------------------------
-- CONSULTA 9: Evolución trimestral de reproducciones
-- con función ventana acumulada
-- Insight: si el acumulado crece trimestre a trimestre,
-- la plataforma está en fase de crecimiento saludable.
-- ------------------------------------------------------------
SELECT
    f.anio,
    f.trimestre,
    COUNT(fr.id_reproduccion)                           AS reproducciones_trimestre,
    SUM(COUNT(fr.id_reproduccion))
        OVER (ORDER BY f.anio, f.trimestre
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                               AS reproducciones_acumuladas,
    ROUND(AVG(fr.completada) * 100, 1)                 AS porcentaje_completado,
    -- Crecimiento vs trimestre anterior
    COUNT(fr.id_reproduccion) -
        LAG(COUNT(fr.id_reproduccion))
        OVER (ORDER BY f.anio, f.trimestre)             AS variacion_vs_anterior
FROM fact_reproducciones fr
INNER JOIN dim_fecha f ON fr.id_fecha = f.id_fecha
GROUP BY f.anio, f.trimestre
ORDER BY f.anio, f.trimestre;

-- CONCLUSIÓN:
-- El acumulado crece trimestre a trimestre llegando a 176 reproducciones
-- totales en 2024 — señal de crecimiento sostenido de la plataforma.
-- El Q1 es el más activo (55 reproducciones) pero cae progresivamente
-- en Q2 (-15) y Q3 (-10) — posible efecto verano donde los usuarios
-- cambian sus hábitos y escuchan menos música en streaming.
-- El Q4 recupera fuerte con 51 reproducciones y una variación de +21
-- respecto al Q3 — el mejor trimestre después del Q1, impulsado
-- claramente por el pico de Diciembre visto en la Consulta 2.
-- El porcentaje de completado mejora cada trimestre: Q1 empieza en 74.6%
-- y Q4 cierra en 94.1% — los usuarios más fieles permanecen
-- en la plataforma en los meses de menor actividad y escuchan mejor.
-- El NULL en variacion_vs_anterior del Q1 es correcto y esperado ya que
-- no hay trimestre anterior con el que comparar, es el punto de partida.
-- Recomendación: reforzar el catálogo y las campañas en Q2 y Q3
-- para reducir la caída estacional y mantener el engagement en verano.



-- ------------------------------------------------------------
-- CONSULTA 10: Segmentación de usuarios por comportamiento
-- Insight: clasifica usuarios en segmentos accionables
-- para campañas de marketing y retención personalizadas.
-- ------------------------------------------------------------
SELECT
    segmento,
    COUNT(*)                        AS total_usuarios,
    ROUND(AVG(reproducciones), 1)  AS avg_reproducciones,
    ROUND(AVG(porcentaje_completado), 1)  AS avg_porcentaje_completado
FROM (
    SELECT
        u.id_usuario,
        u.nombre,
        u.plan,
        COUNT(fr.id_reproduccion)           AS reproducciones,
        ROUND(AVG(fr.completada) * 100, 1) AS porcentaje_completado,
        CASE
            WHEN COUNT(fr.id_reproduccion) >= 10
                 AND AVG(fr.completada) >= 0.8
                 THEN 'Power User'
            WHEN COUNT(fr.id_reproduccion) >= 5
                 AND AVG(fr.completada) >= 0.6
                 THEN 'Usuario Activo'
            WHEN COUNT(fr.id_reproduccion) >= 2
                 THEN 'Usuario Ocasional'
            ELSE 'Usuario Inactivo'
        END AS segmento
    FROM dim_usuarios u
    LEFT JOIN fact_reproducciones fr ON u.id_usuario = fr.id_usuario
    GROUP BY u.id_usuario, u.nombre, u.plan
) segmentados
GROUP BY segmento
ORDER BY avg_reproducciones DESC;

-- CONCLUSIÓN:
-- Todos los usuarios de la plataforma se concentran en solo 2 segmentos:
-- 28 usuarios activos (5.8 reproducciones de media, 87.4% completado)
-- y 2 Usuarios Ocasionales (6.5 reproducciones pero solo 53.6% completado).
-- No hay ningún power user ni usuario inactivo en la plataforma.
-- La ausencia de power users indica que ningún usuario supera
-- las 10 reproducciones con más del 80% de completado simultáneamente
-- — el umbral es exigente y ninguno lo alcanza en 2024.
-- Los 2 usuarios ocasionales tienen paradójicamente más reproducciones
-- promedio (6.5) que los activos (5.8) pero su completado es muy bajo
-- (53.6%) — escuchan muchas canciones pero las abandonan a mitad,
-- lo que los penaliza en la clasificación.
-- Recomendación: bajar el umbral de power user a 7 reproducciones
-- para identificar mejor a los usuarios más valiosos, y diseñar
-- campañas específicas para los  ocasionales para mejorar
-- su engagement y convertirlos en usuarios activos.



-- ------------------------------------------------------------
-- CONSULTA 11: Artistas con mayor duración media escuchada
-- Insight: los artistas donde la gente escucha más segundos
-- por reproducción generan mayor tiempo de sesión —
-- KPI clave para retención en plataformas de streaming.
-- ------------------------------------------------------------
SELECT
    a.nombre_artista,
    a.genero_principal,
    COUNT(fr.id_reproduccion)                       AS total_reproducciones,
    ROUND(AVG(fr.duracion_escuchada), 1)            AS avg_seg_escuchados,
    ROUND(AVG(c.duracion_seg), 1)                   AS avg_duracion_cancion,
    fn_duracion_formato(
        CAST(AVG(fr.duracion_escuchada) AS UNSIGNED)
    )                                               AS avg_escuchado_formato,
    ROUND(
        AVG(fr.duracion_escuchada) / AVG(c.duracion_seg) * 100
    , 1)                                            AS porcentaje_cancion_escuchada
FROM fact_reproducciones fr
INNER JOIN dim_canciones c ON fr.id_cancion = c.id_cancion
INNER JOIN dim_artistas  a ON c.id_artista  = a.id_artista
GROUP BY a.id_artista, a.nombre_artista, a.genero_principal
HAVING COUNT(fr.id_reproduccion) >= 2
ORDER BY avg_seg_escuchados DESC
LIMIT 10;

-- CONCLUSIÓN:
-- Drake lidera con 303.2 segundos de media escuchados por reproducción
-- (5m 3s) y 91.6% de canción escuchada — sus canciones son largas
-- y la gente las escucha casi enteras.
-- Coldplay, Beyoncé, Doja Cat y The Weeknd tienen 100% de canción
-- escuchada — sus usuarios nunca abandonan sus canciones,
-- lo que los convierte en los artistas con mayor fidelidad absoluta.
-- Dato interesante: Coldplay y Arctic Monkeys son los únicos artistas
-- de Rock en el top 10 — el Rock genera sesiones de escucha largas
-- aunque no sea el género más reproducido en volumen.
-- Bad Bunny destaca como el único Reggaeton en este ranking (95.3%)
-- confirmando que es el artista más completo: alto volumen
-- de reproducciones Y alta fidelidad de escucha.
-- Billie Eilish tiene el porcentaje más bajo del ranking (81.9%)
-- pese a estar en el top — sus canciones se escuchan mucho
-- pero no siempre hasta el final.
-- Recomendación: Drake, Coldplay y Beyoncé son los candidatos
-- perfectos para contenido exclusivo — retienen al usuario
-- más tiempo en la plataforma por reproducción.




-- ------------------------------------------------------------
-- CONSULTA 12: Canciones que se abandonan más
-- Insight: canciones con baja tasa de completado pueden
-- tener problemas de calidad, intro demasiado larga o
-- simplemente no encajan con el gusto del usuario.
-- Candidatas a ser retiradas de playlists editoriales.
-- ------------------------------------------------------------
SELECT
    c.titulo,
    a.nombre_artista,
    c.genero,
    fn_duracion_formato(c.duracion_seg)             AS duracion_total,
    COUNT(fr.id_reproduccion)                       AS total_reproducciones,
    ROUND(AVG(fr.completada) * 100, 1)             AS porcentaje_completado,
    ROUND(AVG(fr.duracion_escuchada), 1)           AS avg_seg_antes_salir
FROM fact_reproducciones fr
INNER JOIN dim_canciones c ON fr.id_cancion = c.id_cancion
INNER JOIN dim_artistas  a ON c.id_artista  = a.id_artista
GROUP BY c.id_cancion, c.titulo, a.nombre_artista, c.genero, c.duracion_seg
HAVING COUNT(fr.id_reproduccion) >= 2
   AND AVG(fr.completada) < 0.7
ORDER BY porcentaje_completado ASC
LIMIT 10;

-- CONCLUSIÓN:
-- Anti-Hero (Taylor Swift) y Happier Than Ever (Billie Eilish) son las
-- canciones más abandonadas con solo 55.6% de completado — empatan
-- como las peores en engagement a pesar de ser artistas muy populares.
-- Los usuarios abandonan Anti-Hero a los 170.9 segundos de media
-- sobre 3m 20s totales — se van antes del último minuto.
-- Happier Than Ever es la más larga del ranking (4m 55s) y se abandona
-- a los 237.2 segundos.
-- N95 de Kendrick Lamar (62.5%) y Malamente de Rosalía (66.7%)
-- completan el ranking de canciones con bajo engagement —
-- ambas son canciones de nicho que no conectan con el perfil
-- general de usuarios de la plataforma.
-- Dato consistente con consultas anteriores: Pop Flamenco y Hip-Hop
-- aparecen de nuevo como géneros con más abandono.
-- Recomendación: retirar estas 4 canciones de las playlists
-- editoriales principales y redirigirlas a playlists de nicho
-- para usuarios con historial de escucha de esos géneros específicos.




-- ============================================================
-- BLOQUE 4: CONSULTAS SOBRE LAS VISTAS DE NEGOCIO
-- ============================================================

-- ------------------------------------------------------------
-- Vista 1: vw_reproducciones_completas
-- Esta vista encapsula los 5 JOINs más frecuentes del modelo.
-- Cualquier analista puede consultar datos completos sin necesidad
-- de conocer la estructura interna de las tablas.
-- Aquí mostramos las 20 reproducciones más recientes con todos
-- sus datos asociados — útil para auditorías y reporting diario.
-- CONCLUSIÓN: la vista devuelve en una sola línea de código
-- lo que sin ella requeriría mas de 15 líneas de JOINs repetidos.
-- Esto reduce errores y hace el código mantenible a largo plazo.
-- ------------------------------------------------------------
SELECT
    nombre_usuario,
    plan_usuario,
    titulo_cancion,
    nombre_artista,
    genero,
    duracion_formato,
    fecha,
    nombre_dia,
    es_fin_semana,
    completada
FROM vw_reproducciones_completas
ORDER BY fecha DESC
LIMIT 20;


-- ------------------------------------------------------------
-- Vista 2: vw_resumen_artistas
-- Esta vista encapsula los JOINs y agregaciones necesarias para
-- calcular los KPIs principales de cada artista automáticamente.
-- Cualquier analista puede consultar el dashboard ejecutivo completo
-- sin necesidad de escribir GROUP BY ni funciones de agregación.
-- Aquí mostramos el ranking de artistas ordenado por reproducciones
-- con sus métricas clave — útil para reporting ejecutivo y
-- decisiones sobre contratación de artistas o exclusividades.
-- CONCLUSIÓN: la vista devuelve en una sola línea de código
-- lo que sin ella requeriría más de 20 líneas de JOINs,
-- GROUP BY y agregaciones repetidas en cada consulta.
-- Esto reduce errores y hace el código mantenible a largo plazo.
-- ------------------------------------------------------------
SELECT
    nombre_artista,
    genero_principal,
    total_reproducciones,
    oyentes_unicos,
    pct_completado,
    avg_duracion_escuchada_seg
FROM vw_resumen_artistas
WHERE total_reproducciones > 0
ORDER BY total_reproducciones DESC;


-- ============================================================
-- BLOQUE 5: RESUMEN DE INSIGHTS DE NEGOCIO
-- ============================================================

-- INSIGHT 1 — Estacionalidad (Consultas 2 y 9):
--   Enero/Febrero y Diciembre son los picos de actividad del año.
--   Diciembre es el mes más alto con 31 reproducciones y 96.8%
--   de completado — impulsado por las vacaciones navideñas.
--   El Q4 recupera +21 reproducciones respecto al Q3.
--   Recomendación: concentrar lanzamientos y campañas de marketing
--   en Enero y Diciembre para aprovechar los picos de audiencia.
--   Reforzar el catálogo en Q2 y Q3 para reducir la caída estacional.

-- INSIGHT 2 — Modelo freemium (Consulta 3):
--   Los usuarios Premium generan más reproducciones totales (66)
--   y más reproducciones por usuario (6.0) que los Free (5.8).
--   Sorprendentemente los usuarios Free completan más canciones
--   (86.5%) que los Premium (81.8%) — al tener límite de saltos
--   aprovechan mejor cada reproducción.
--   Los Estudiante son los más fieles con 93.1% de completado.
--   Recomendación: campañas de conversión dirigidas a usuarios
--   Free activos tienen alto potencial de retorno económico.

-- INSIGHT 3 — Engagement por artista (Consultas 4, 11 y vista 2):
--   The Weeknd lidera con 14 reproducciones y 100% de completado
--   siendo el artista más reproducido Y más fiel de la plataforma.
--   Drake genera el mayor tiempo de sesión con 303 segundos de
--   media escuchados por reproducción — máxima retención.
--   J Balvin, Coldplay, Beyoncé, Dua Lipa y Doja Cat tienen
--   100% de completado — sus oyentes nunca abandonan sus canciones.
--   Recomendación: estos artistas son candidatos ideales para
--   exclusividades y contenido patrocinado — alto alcance
--   combinado con máxima fidelidad de escucha.

-- INSIGHT 4 — Géneros y abandono (Consultas 5, 7 y 12):
--   El Reggaeton es el género dominante en todos los planes
--   excepto Familiar donde lidera el Pop.
--   Las canciones más abandonadas son Anti-Hero (Taylor Swift)
--   y Happier Than Ever (Billie Eilish) con solo 55.6% de completado
--   pese a ser artistas muy populares.
--   El Urban tiene el peor completado entre Premium (33.3%).
--   Recomendación: retirar canciones con bajo completado de
--   playlists editoriales principales y crear playlists de nicho
--   para Pop Flamenco y Urban dirigidas a sus oyentes específicos.

-- INSIGHT 5 — Comportamiento por día (Consulta 6):
--   Los días laborables generan más del doble de reproducciones
--   (125) que los fines de semana (51) — los usuarios escuchan
--   música principalmente mientras trabajan o estudian.
--   El completado es igual en ambos casos (~84%) — el tipo de
--   día no afecta a la calidad de escucha, solo al volumen.
--   Recomendación: orientar notificaciones push y lanzamientos
--   de contenido nuevo a días laborables para maximizar el alcance.
-- ============================================================