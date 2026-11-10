-- ==============================================================================
-- Netflix Data Analysis Project: 02_views_and_indexes.sql
-- Description: Analytical views and calculated dimensional structures
--              to accelerate reporting, business intelligence, and complex queries.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- View 1: v_titles_enriched
-- Flattened 360-degree view combining core title attributes with aggregated dimensions
-- and calculated streaming latency metrics.
-- ------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_titles_enriched;
CREATE VIEW v_titles_enriched AS
SELECT
    t.show_id,
    t.type,
    t.title,
    t.date_added,
    CAST(strftime('%Y', t.date_added) AS INTEGER) AS year_added,
    CAST(strftime('%m', t.date_added) AS INTEGER) AS month_added,
    t.release_year,
    CASE 
        WHEN t.date_added IS NOT NULL 
        THEN CAST(strftime('%Y', t.date_added) AS INTEGER) - t.release_year 
        ELSE NULL 
    END AS years_to_streaming,
    t.rating,
    t.duration,
    t.duration_int,
    t.duration_unit,
    (SELECT GROUP_CONCAT(d.director_name, ', ')
     FROM title_directors td
     JOIN directors d ON td.director_id = d.director_id
     WHERE td.show_id = t.show_id) AS directors,
    (SELECT GROUP_CONCAT(c.country_name, ', ')
     FROM title_countries tc
     JOIN countries c ON tc.country_id = c.country_id
     WHERE tc.show_id = t.show_id) AS countries,
    (SELECT GROUP_CONCAT(g.genre_name, ', ')
     FROM title_genres tg
     JOIN genres g ON tg.genre_id = g.genre_id
     WHERE tg.show_id = t.show_id) AS genres,
    t.description
FROM titles t;

-- ------------------------------------------------------------------------------
-- View 2: v_movie_catalog
-- Dedicated analytical view for Movies with runtime classification
-- ------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_movie_catalog;
CREATE VIEW v_movie_catalog AS
SELECT
    t.show_id,
    t.title,
    t.release_year,
    t.date_added,
    CAST(strftime('%Y', t.date_added) AS INTEGER) AS year_added,
    t.rating,
    t.duration_int AS runtime_minutes,
    CASE
        WHEN t.duration_int < 60 THEN 'Short (< 60m)'
        WHEN t.duration_int BETWEEN 60 AND 89 THEN 'Standard (60-89m)'
        WHEN t.duration_int BETWEEN 90 AND 120 THEN 'Feature (90-120m)'
        WHEN t.duration_int BETWEEN 121 AND 150 THEN 'Extended (121-150m)'
        ELSE 'Epic (> 150m)'
    END AS runtime_category,
    t.description
FROM titles t
WHERE t.type = 'Movie';

-- ------------------------------------------------------------------------------
-- View 3: v_tv_series_catalog
-- Dedicated analytical view for TV Shows with series longevity cohorts
-- ------------------------------------------------------------------------------
DROP VIEW IF EXISTS v_tv_series_catalog;
CREATE VIEW v_tv_series_catalog AS
SELECT
    t.show_id,
    t.title,
    t.release_year,
    t.date_added,
    CAST(strftime('%Y', t.date_added) AS INTEGER) AS year_added,
    t.rating,
    t.duration_int AS total_seasons,
    CASE
        WHEN t.duration_int = 1 THEN 'Limited / 1 Season'
        WHEN t.duration_int BETWEEN 2 AND 3 THEN 'Mid-tier (2-3 Seasons)'
        WHEN t.duration_int BETWEEN 4 AND 6 THEN 'Established (4-6 Seasons)'
        ELSE 'Long-Running (7+ Seasons)'
    END AS longevity_tier,
    t.description
FROM titles t
WHERE t.type = 'TV Show';
