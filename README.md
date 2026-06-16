# Proyecto SQL: Plataforma de Streaming de Música 🎵

## Descripción

Modelo de base de datos relacional que simula una plataforma de streaming de música tipo Spotify.
El proyecto incluye diseño del esquema dimensional, carga de datos ficticios coherentes y un análisis
exploratorio completo con insights de negocio extraídos mediante SQL.

---

## Motor y herramientas

- **Motor SQL:** MySQL 8.0+
- **IDE:** MySQL Workbench
- **Modelo:** Esquema en estrella (Star Schema)

---

## Estructura del proyecto

📁 proyecto-sql-streaming/

- 01_schema.sql → Creación de tablas, PKs, FKs, constraints, índices, función y vistas de negocio
- 02_data.sql → Carga de datos (INSERT), procedimiento de calendario, UPDATEs y transacciones
- 03_eda.sql → Análisis exploratorio completo: limpieza, validación y 12 consultas analíticas
- README.md → Este archivo
- model.png → Diagrama ER del modelo de datos

- ---

## Modelo de datos
<img width="931" height="779" alt="x" src="https://github.com/user-attachments/assets/3116b894-ffab-4bcc-897e-1877d204fd68" />

El modelo sigue una arquitectura **estrella (Star Schema)** con 1 tabla de hechos y 5 dimensiones:

| Tabla | Tipo | Granularidad | Registros |
|---|---|---|---|
| `fact_reproducciones` | Hechos | 1 fila = 1 reproducción | ~220 |
| `dim_usuarios` | Dimensión | 1 fila = 1 usuario | 30 |
| `dim_canciones` | Dimensión | 1 fila = 1 canción | 40 |
| `dim_artistas` | Dimensión | 1 fila = 1 artista | 20 |
| `dim_albumes` | Dimensión | 1 fila = 1 álbum | 20 |
| `dim_fecha` | Dimensión | 1 fila = 1 día | 366 |

---

## Decisiones de diseño

### Primary Keys
Todas las tablas usan claves subrogadas `INT AUTO_INCREMENT` — independientes
del negocio para permitir cambios sin romper integridad referencial.
Excepción: `dim_fecha` usa `INT` en formato `YYYYMMDD` — patrón estándar
en Data Warehousing que permite joins directos sin lookup adicional.

### Foreign Keys
Todas las FKs usan `ON DELETE RESTRICT` para proteger la integridad de los datos
y `ON UPDATE CASCADE` para propagar cambios automáticamente.

### Normalización
El modelo está en **3FN** con una desnormalización deliberada: `dim_canciones`
incluye `id_artista` aunque ya esté en `dim_albumes`. Esto es una práctica
estándar en modelos dimensionales para evitar JOINs innecesarios en consultas analíticas.

### Constraints aplicados
- `NOT NULL` en todas las columnas críticas
- `UNIQUE` en `email` de usuarios y en `fecha` del calendario
- `CHECK` en edades (13-120), BPM (40-300), duración (15-3600 seg), debut (1900-2025)
- `DEFAULT` en plan, país, completada y BPM

---

## Contenido del EDA (03_eda.sql)

### Bloque 1 — Calidad de datos
- Detección de NULLs en tablas críticas
- Detección de duplicados con `GROUP BY` y `RANK() OVER (PARTITION BY)`
- Outliers: edades fuera de rango, duraciones imposibles, BPM inválidos
- Validación de fechas con `CAST` y `STR_TO_DATE`

### Bloque 2 — Análisis descriptivo
- Resumen general del volumen de datos
- Distribución de usuarios por plan y país
- Estadísticas de edad y géneros musicales
- Métricas globales de reproducciones

### Bloque 3 — 12 consultas analíticas de negocio
| # | Consulta | Técnicas SQL |
|---|---|---|
| 1 | Top 10 canciones más reproducidas | INNER JOIN, GROUP BY, ORDER BY |
| 2 | Reproducciones por mes | JOIN, funciones de fecha, GROUP BY |
| 3 | Comparativa Free vs Premium | JOIN, GROUP BY, AVG, COUNT DISTINCT |
| 4 | Top artistas por oyentes únicos | LEFT JOIN, COUNT DISTINCT |
| 5 | Géneros más escuchados por plan | JOIN múltiple, GROUP BY, CASE |
| 6 | Fin de semana vs días laborables | JOIN, CASE, GROUP BY |
| 7 | Ranking por tasa de completado | CTEs encadenadas, RANK() OVER PARTITION BY |
| 8 | Usuarios más activos con género favorito | CTEs encadenadas, subquery, window function |
| 9 | Evolución trimestral acumulada | SUM() OVER, LAG() OVER, GROUP BY |
| 10 | Segmentación de usuarios | CASE, subquery, LEFT JOIN |
| 11 | Artistas con mayor duración media | JOIN, AVG, función propia |
| 12 | Canciones que se abandonan más | JOIN, HAVING, AVG, ORDER BY |

### Bloque 4 — Consultas sobre vistas
- `vw_reproducciones_completas` — reporting diario y auditorías
- `vw_resumen_artistas` — dashboard ejecutivo de artistas

---

## Principales insights de negocio

**Insight 1 — Estacionalidad:**
Diciembre es el mes más activo (31 reproducciones, 96.8% completado) seguido de
Enero y Febrero. El Q4 recupera +21 reproducciones respecto al Q3.
→ Concentrar lanzamientos y campañas en Enero y Diciembre.

**Insight 2 — Modelo freemium:**
Los usuarios Premium generan más volumen (6.0 reproducciones/usuario vs 5.8 Free)
pero los usuarios Free completan más canciones (86.5% vs 81.8%) al tener límite de saltos.
Los Estudiante son los más fieles con 93.1% de completado.
→ Los usuarios Free activos tienen alto potencial de conversión a Premium.

**Insight 3 — Engagement por artista:**
The Weeknd lidera con 14 reproducciones y 100% de completado.
Drake genera el mayor tiempo de sesión con 303 segundos de media por reproducción.
J Balvin, Coldplay, Beyoncé, Dua Lipa y Doja Cat tienen 100% de completado.
→ Candidatos ideales para exclusividades y contenido patrocinado.

**Insight 4 — Géneros y abandono:**
El Reggaeton domina en todos los planes excepto Familiar donde lidera el Pop.
Anti-Hero y Happier Than Ever tienen solo 55.6% de completado pese a ser muy populares.
El Urban tiene el peor completado entre Premium (33.3%).
→ Retirar canciones con bajo completado de playlists editoriales principales.

**Insight 5 — Comportamiento por día:**
Los días laborables generan más del doble de reproducciones que los fines de semana
(125 vs 51) — los usuarios escuchan música principalmente mientras trabajan o estudian.
→ Orientar notificaciones push y lanzamientos a días laborables.

---

## Cómo ejecutar el proyecto

1. Abre MySQL Workbench y conéctate a tu servidor
2. Ejecuta `01_schema.sql` → crea la base de datos y el modelo
3. Ejecuta `02_data.sql` → carga todos los datos
4. Ejecuta `03_eda.sql` → análisis exploratorio completo

> Los scripts usan `DROP DATABASE IF EXISTS` y `IF NOT EXISTS` para poder
> ejecutarse desde cero sin errores en cualquier momento.

---

## Autor
[Aroa Barberán Martín]
Junio 2026
