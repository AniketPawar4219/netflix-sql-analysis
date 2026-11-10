-- ==============================================================================
-- NETFLIX ADVANCED SQL DATA ANALYSIS PROJECT
-- Script: sql/business_queries.sql
-- Description: 15 Advanced Business Questions showcasing CTEs, Window Functions,
--              Multi-way & Self-Joins, Date Arithmetic, and Analytical Groupings.
-- Engine: SQLite 3 / DuckDB
-- ==============================================================================

-- ==============================================================================
-- QUERY 01: Content Ingestion Velocity & Year-over-Year (YoY) Growth Rate
-- Business Problem:
--   To understand Netflix's catalog expansion strategy, determine the total volume
--   of Movies and TV Shows added each calendar year, retrieve the previous year's
--   additions using LAG(), and calculate the YoY percentage growth rate for each content type.
-- ==============================================================================
WITH yearly_type_counts AS (
    SELECT
        CAST(strftime('%Y', date_added) AS INTEGER) AS year_added,
        type,
        COUNT(*) AS total_additions
    FROM titles
    WHERE date_added IS NOT NULL
    GROUP BY year_added, type
),
growth_calc AS (
    SELECT
        year_added,
        type,
        total_additions,
        LAG(total_additions) OVER (PARTITION BY type ORDER BY year_added) AS prev_year_additions
    FROM yearly_type_counts
)
SELECT
    year_added,
    type,
    total_additions,
    COALESCE(prev_year_additions, 0) AS prev_year_additions,
    ROUND(
        CASE 
            WHEN prev_year_additions IS NULL OR prev_year_additions = 0 THEN 0.0
            ELSE ((total_additions - prev_year_additions) * 100.0) / prev_year_additions
        END, 2
    ) AS yoy_growth_pct
FROM growth_calc
WHERE year_added >= 2015
ORDER BY year_added DESC, type ASC;


-- ==============================================================================
-- QUERY 02: Top 10 Actors by Content Segment (Movies vs. TV Shows)
-- Business Problem:
--   Identify the top 10 most prolific actors specifically within Movies compared
--   to TV Shows. Utilize DENSE_RANK() partitioned by content type to handle ties,
--   and calculate each actor's career span on the platform.
-- ==============================================================================
WITH actor_appearances AS (
    SELECT
        t.type,
        a.actor_name,
        COUNT(DISTINCT t.show_id) AS total_appearances,
        MIN(t.release_year) AS earliest_year,
        MAX(t.release_year) AS latest_year
    FROM actors a
    JOIN title_actors ta ON a.actor_id = ta.actor_id
    JOIN titles t ON ta.show_id = t.show_id
    GROUP BY t.type, a.actor_name
),
ranked_actors AS (
    SELECT
        type,
        actor_name,
        total_appearances,
        earliest_year,
        latest_year,
        DENSE_RANK() OVER (PARTITION BY type ORDER BY total_appearances DESC) AS rank_in_type
    FROM actor_appearances
)
SELECT
    type,
    rank_in_type,
    actor_name,
    total_appearances,
    earliest_year || ' - ' || latest_year AS career_span
FROM ranked_actors
WHERE rank_in_type <= 10
ORDER BY type ASC, rank_in_type ASC, actor_name ASC;


-- ==============================================================================
-- QUERY 03: Rolling 3-Year Ingestion Average & Content Expansion Trajectory
-- Business Problem:
--   Content acquisition deals can create seasonal and yearly spikes. Calculate
--   the 3-year rolling average of total additions alongside cumulative catalog
--   volume to measure true long-term catalog expansion velocity.
-- ==============================================================================
WITH yearly_inflow AS (
    SELECT
        CAST(strftime('%Y', date_added) AS INTEGER) AS calendar_year,
        COUNT(DISTINCT show_id) AS titles_added,
        COUNT(DISTINCT CASE WHEN type = 'Movie' THEN show_id END) AS movies_added,
        COUNT(DISTINCT CASE WHEN type = 'TV Show' THEN show_id END) AS tv_shows_added
    FROM titles
    WHERE date_added IS NOT NULL
    GROUP BY calendar_year
)
SELECT
    calendar_year,
    titles_added,
    movies_added,
    tv_shows_added,
    ROUND(AVG(titles_added) OVER (
        ORDER BY calendar_year 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 1) AS rolling_3yr_avg_additions,
    SUM(titles_added) OVER (
        ORDER BY calendar_year
    ) AS cumulative_catalog_size
FROM yearly_inflow
WHERE calendar_year >= 2012
ORDER BY calendar_year ASC;


-- ==============================================================================
-- QUERY 04: Strategic Director-Actor Power Partnerships (High-Yield Collaborations)
-- Business Problem:
--   Uncover repeat creative partnerships between directors and actors across
--   Netflix titles. Identify duos that have collaborated on at least 4 catalog
--   projects, measuring partnership lifespan and catalog footprint.
-- ==============================================================================
WITH collaborations AS (
    SELECT
        d.director_name,
        a.actor_name,
        COUNT(DISTINCT t.show_id) AS titles_together,
        MIN(t.release_year) AS first_collab_year,
        MAX(t.release_year) AS latest_collab_year,
        GROUP_CONCAT(DISTINCT t.title) AS sample_titles
    FROM titles t
    JOIN title_directors td ON t.show_id = td.show_id
    JOIN directors d ON td.director_id = d.director_id
    JOIN title_actors ta ON t.show_id = ta.show_id
    JOIN actors a ON ta.actor_id = a.actor_id
    GROUP BY d.director_name, a.actor_name
    HAVING COUNT(DISTINCT t.show_id) >= 4
)
SELECT
    director_name,
    actor_name,
    titles_together,
    (latest_collab_year - first_collab_year) AS partnership_span_years,
    first_collab_year || ' - ' || latest_collab_year AS years_active,
    sample_titles
FROM collaborations
ORDER BY titles_together DESC, director_name ASC, actor_name ASC
LIMIT 15;


-- ==============================================================================
-- QUERY 05: Country Catalog Genre Saturation Index
-- Business Problem:
--   For the top 5 content-producing countries by total titles, analyze the top 3
--   genres and their catalog penetration percentage (share of country's titles).
-- ==============================================================================
WITH top_countries AS (
    SELECT
        c.country_id,
        c.country_name,
        COUNT(DISTINCT tc.show_id) AS total_country_titles,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT tc.show_id) DESC) AS country_rank
    FROM countries c
    JOIN title_countries tc ON c.country_id = tc.country_id
    GROUP BY c.country_id, c.country_name
),
country_genre_counts AS (
    SELECT
        tc_top.country_name,
        tc_top.country_rank,
        tc_top.total_country_titles,
        g.genre_name,
        COUNT(DISTINCT t.show_id) AS genre_titles,
        DENSE_RANK() OVER (
            PARTITION BY tc_top.country_name 
            ORDER BY COUNT(DISTINCT t.show_id) DESC
        ) AS genre_rank_in_country
    FROM top_countries tc_top
    JOIN title_countries tc ON tc_top.country_id = tc.country_id
    JOIN titles t ON tc.show_id = t.show_id
    JOIN title_genres tg ON t.show_id = tg.show_id
    JOIN genres g ON tg.genre_id = g.genre_id
    WHERE tc_top.country_rank <= 5
    GROUP BY tc_top.country_name, tc_top.country_rank, tc_top.total_country_titles, g.genre_name
)
SELECT
    country_name,
    country_rank,
    genre_rank_in_country,
    genre_name,
    genre_titles,
    total_country_titles,
    ROUND((genre_titles * 100.0) / total_country_titles, 2) AS catalog_penetration_pct
FROM country_genre_counts
WHERE genre_rank_in_country <= 3
ORDER BY country_rank ASC, genre_rank_in_country ASC;


-- ==============================================================================
-- QUERY 06: Theatrical-to-Streaming Release Window Latency Analysis
-- Business Problem:
--   Measure the latency between content theatrical/original release year and
--   the year it was ingested onto Netflix across three strategic ingestion eras
--   (<2016, 2016-2018, 2019-2021). Track percentage of Same-Year vs Vintage content.
-- ==============================================================================
WITH latency_base AS (
    SELECT
        show_id,
        type,
        release_year,
        CAST(strftime('%Y', date_added) AS INTEGER) AS year_added,
        CAST(strftime('%Y', date_added) AS INTEGER) - release_year AS latency_years,
        CASE
            WHEN CAST(strftime('%Y', date_added) AS INTEGER) < 2016 THEN 'Early Intake (< 2016)'
            WHEN CAST(strftime('%Y', date_added) AS INTEGER) BETWEEN 2016 AND 2018 THEN 'Growth Wave (2016-2018)'
            ELSE 'Peak Era (2019-2021)'
        END AS intake_era
    FROM titles
    WHERE date_added IS NOT NULL AND release_year IS NOT NULL AND release_year > 0
),
categorized AS (
    SELECT
        intake_era,
        type,
        show_id,
        latency_years,
        CASE
            WHEN latency_years <= 0 THEN 'Same Year Premiere (0 yrs)'
            WHEN latency_years BETWEEN 1 AND 2 THEN 'Recent Window (1-2 yrs)'
            WHEN latency_years BETWEEN 3 AND 5 THEN 'Mid Catalog (3-5 yrs)'
            WHEN latency_years BETWEEN 6 AND 10 THEN 'Deep Catalog (6-10 yrs)'
            ELSE 'Archive / Vintage (>10 yrs)'
        END AS freshness_bucket
    FROM latency_base
    WHERE latency_years >= 0
)
SELECT
    intake_era,
    type,
    COUNT(*) AS total_titles,
    ROUND(AVG(latency_years), 1) AS avg_latency_years,
    ROUND(100.0 * SUM(CASE WHEN freshness_bucket = 'Same Year Premiere (0 yrs)' THEN 1 ELSE 0 END) / COUNT(*), 1) AS same_year_pct,
    ROUND(100.0 * SUM(CASE WHEN freshness_bucket = 'Recent Window (1-2 yrs)' THEN 1 ELSE 0 END) / COUNT(*), 1) AS recent_window_pct,
    ROUND(100.0 * SUM(CASE WHEN freshness_bucket IN ('Mid Catalog (3-5 yrs)', 'Deep Catalog (6-10 yrs)') THEN 1 ELSE 0 END) / COUNT(*), 1) AS catalog_pct,
    ROUND(100.0 * SUM(CASE WHEN freshness_bucket = 'Archive / Vintage (>10 yrs)' THEN 1 ELSE 0 END) / COUNT(*), 1) AS vintage_pct
FROM categorized
GROUP BY intake_era, type
ORDER BY intake_era ASC, type ASC;


-- ==============================================================================
-- QUERY 07: Bilateral International Co-Production Network
-- Business Problem:
--   Map international co-production hubs by identifying which pairs of nations
--   most frequently co-produce titles together using self-joins on title_countries.
-- ==============================================================================
WITH bilateral_pairs AS (
    SELECT
        tc1.show_id,
        c1.country_name AS country_a,
        c2.country_name AS country_b
    FROM title_countries tc1
    JOIN title_countries tc2 ON tc1.show_id = tc2.show_id AND tc1.country_id < tc2.country_id
    JOIN countries c1 ON tc1.country_id = c1.country_id
    JOIN countries c2 ON tc2.country_id = c2.country_id
),
pair_summary AS (
    SELECT
        country_a,
        country_b,
        COUNT(DISTINCT show_id) AS co_production_count,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT show_id) DESC) AS rank
    FROM bilateral_pairs
    GROUP BY country_a, country_b
)
SELECT
    rank,
    country_a || ' <-> ' || country_b AS bilateral_corridor,
    country_a,
    country_b,
    co_production_count
FROM pair_summary
WHERE rank <= 15
ORDER BY rank ASC, country_a ASC;


-- ==============================================================================
-- QUERY 08: Movie Runtime and TV Series Seasonality Distribution Analysis
-- Business Problem:
--   Compute quartile distribution of Movie runtimes (in minutes) via NTILE(4)
--   and season tier breakdown of TV series, highlighting min, max, and avg metrics.
-- ==============================================================================
WITH movie_quartiles AS (
    SELECT
        show_id,
        title,
        duration_int AS runtime_minutes,
        NTILE(4) OVER (ORDER BY duration_int) AS runtime_quartile
    FROM titles
    WHERE type = 'Movie' AND duration_int IS NOT NULL
),
movie_summary AS (
    SELECT
        'Movie' AS content_type,
        'Q' || runtime_quartile AS quartile_or_tier,
        COUNT(*) AS title_count,
        MIN(runtime_minutes) AS min_metric,
        MAX(runtime_minutes) AS max_metric,
        ROUND(AVG(runtime_minutes), 1) AS avg_metric
    FROM movie_quartiles
    GROUP BY runtime_quartile
),
tv_summary AS (
    SELECT
        'TV Show' AS content_type,
        CASE
            WHEN duration_int = 1 THEN '1 Season (Limited)'
            WHEN duration_int BETWEEN 2 AND 3 THEN '2-3 Seasons (Mid-Run)'
            WHEN duration_int BETWEEN 4 AND 6 THEN '4-6 Seasons (Established)'
            ELSE '7+ Seasons (Legacy)'
        END AS quartile_or_tier,
        COUNT(*) AS title_count,
        MIN(duration_int) AS min_metric,
        MAX(duration_int) AS max_metric,
        ROUND(AVG(duration_int), 1) AS avg_metric
    FROM titles
    WHERE type = 'TV Show' AND duration_int IS NOT NULL
    GROUP BY quartile_or_tier
)
SELECT * FROM movie_summary
UNION ALL
SELECT * FROM tv_summary
ORDER BY content_type DESC, min_metric ASC;


-- ==============================================================================
-- QUERY 09: Genre Co-occurrence & Market Basket Affinity Analysis
-- Business Problem:
--   Determine which genre pairings occur most frequently together on titles
--   to analyze content bundling and multi-genre tagging strategy.
-- ==============================================================================
WITH genre_baskets AS (
    SELECT
        tg1.show_id,
        g1.genre_name AS genre_a,
        g2.genre_name AS genre_b
    FROM title_genres tg1
    JOIN title_genres tg2 ON tg1.show_id = tg2.show_id AND tg1.genre_id < tg2.genre_id
    JOIN genres g1 ON tg1.genre_id = g1.genre_id
    JOIN genres g2 ON tg2.genre_id = g2.genre_id
),
pair_frequencies AS (
    SELECT
        genre_a,
        genre_b,
        COUNT(DISTINCT show_id) AS cooccurrence_count,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT show_id) DESC) AS ranking
    FROM genre_baskets
    GROUP BY genre_a, genre_b
)
SELECT
    ranking,
    genre_a || ' & ' || genre_b AS genre_pair,
    genre_a,
    genre_b,
    cooccurrence_count,
    ROUND(cooccurrence_count * 100.0 / (SELECT COUNT(*) FROM titles), 2) AS catalog_cooccurrence_pct
FROM pair_frequencies
WHERE ranking <= 15
ORDER BY ranking ASC, genre_a ASC;


-- ==============================================================================
-- QUERY 10: Cumulative Catalog Trajectory & Content Portfolio Mix Ratio
-- Business Problem:
--   Track the cumulative expansion of Movies vs. TV Shows over time and measure
--   how the portfolio mix ratio (Movie % vs. TV Show %) stabilized historically.
-- ==============================================================================
WITH yearly_mix AS (
    SELECT
        CAST(strftime('%Y', date_added) AS INTEGER) AS year_added,
        COUNT(CASE WHEN type = 'Movie' THEN 1 END) AS annual_movies,
        COUNT(CASE WHEN type = 'TV Show' THEN 1 END) AS annual_tv_shows,
        COUNT(*) AS annual_total
    FROM titles
    WHERE date_added IS NOT NULL
    GROUP BY year_added
),
cumulative_mix AS (
    SELECT
        year_added,
        annual_movies,
        annual_tv_shows,
        annual_total,
        SUM(annual_movies) OVER (ORDER BY year_added) AS cum_movies,
        SUM(annual_tv_shows) OVER (ORDER BY year_added) AS cum_tv_shows,
        SUM(annual_total) OVER (ORDER BY year_added) AS cum_total
    FROM yearly_mix
)
SELECT
    year_added,
    annual_movies,
    annual_tv_shows,
    annual_total,
    cum_movies,
    cum_tv_shows,
    cum_total,
    ROUND((cum_movies * 100.0) / cum_total, 2) AS cum_movie_share_pct,
    ROUND((cum_tv_shows * 100.0) / cum_total, 2) AS cum_tv_share_pct
FROM cumulative_mix
WHERE year_added >= 2014
ORDER BY year_added ASC;


-- ==============================================================================
-- QUERY 11: Top 1 Dominant Director per Genre by Catalog Footprint
-- Business Problem:
--   For each genre, identify the #1 most represented director, calculate their
--   title count in that genre, and their genre portfolio share percentage.
-- ==============================================================================
WITH director_genre_counts AS (
    SELECT
        g.genre_name,
        d.director_name,
        COUNT(DISTINCT t.show_id) AS titles_in_genre,
        (SELECT COUNT(DISTINCT td2.show_id) 
         FROM title_directors td2 
         WHERE td2.director_id = d.director_id) AS director_total_titles
    FROM genres g
    JOIN title_genres tg ON g.genre_id = tg.genre_id
    JOIN titles t ON tg.show_id = t.show_id
    JOIN title_directors td ON t.show_id = td.show_id
    JOIN directors d ON td.director_id = d.director_id
    GROUP BY g.genre_name, d.director_name, d.director_id
),
ranked_directors AS (
    SELECT
        genre_name,
        director_name,
        titles_in_genre,
        director_total_titles,
        ROUND((titles_in_genre * 100.0) / director_total_titles, 1) AS genre_share_pct,
        ROW_NUMBER() OVER (
            PARTITION BY genre_name 
            ORDER BY titles_in_genre DESC, director_total_titles DESC, director_name ASC
        ) AS rank_in_genre
    FROM director_genre_counts
)
SELECT
    genre_name,
    director_name,
    titles_in_genre,
    director_total_titles,
    genre_share_pct
FROM ranked_directors
WHERE rank_in_genre = 1
ORDER BY titles_in_genre DESC, genre_name ASC
LIMIT 15;


-- ==============================================================================
-- QUERY 12: Actor Specialization vs. Versatility Index
-- Business Problem:
--   Analyze actors with at least 15 catalog titles, excluding generic umbrella tags
--   ('International Movies', 'International TV Shows'), to identify high-specialists
--   (>=70% titles in one genre) versus versatile generalists.
-- ==============================================================================
WITH actor_totals AS (
    SELECT
        a.actor_id,
        a.actor_name,
        COUNT(DISTINCT ta.show_id) AS total_titles,
        COUNT(DISTINCT tg.genre_id) AS distinct_genres
    FROM actors a
    JOIN title_actors ta ON a.actor_id = ta.actor_id
    JOIN title_genres tg ON ta.show_id = tg.show_id
    JOIN genres g ON tg.genre_id = g.genre_id
    WHERE g.genre_name NOT IN ('International Movies', 'International TV Shows')
    GROUP BY a.actor_id, a.actor_name
    HAVING COUNT(DISTINCT ta.show_id) >= 15
),
actor_genre_distribution AS (
    SELECT
        at.actor_id,
        at.actor_name,
        at.total_titles,
        at.distinct_genres,
        g.genre_name,
        COUNT(DISTINCT ta.show_id) AS titles_in_genre,
        ROW_NUMBER() OVER (
            PARTITION BY at.actor_id 
            ORDER BY COUNT(DISTINCT ta.show_id) DESC
        ) AS genre_rank
    FROM actor_totals at
    JOIN title_actors ta ON at.actor_id = ta.actor_id
    JOIN title_genres tg ON ta.show_id = tg.show_id
    JOIN genres g ON tg.genre_id = g.genre_id
    WHERE g.genre_name NOT IN ('International Movies', 'International TV Shows')
    GROUP BY at.actor_id, at.actor_name, at.total_titles, at.distinct_genres, g.genre_name
)
SELECT
    actor_name,
    total_titles,
    distinct_genres,
    genre_name AS primary_genre,
    titles_in_genre AS primary_genre_titles,
    ROUND((titles_in_genre * 100.0) / total_titles, 1) AS primary_genre_concentration_pct,
    CASE
        WHEN (titles_in_genre * 100.0) / total_titles >= 70.0 THEN 'High Specialist (>=70%)'
        WHEN (titles_in_genre * 100.0) / total_titles BETWEEN 45.0 AND 69.9 THEN 'Moderate Specialist (45-70%)'
        ELSE 'Versatile Generalist (<45%)'
    END AS versatility_profile
FROM actor_genre_distribution
WHERE genre_rank = 1
ORDER BY primary_genre_concentration_pct DESC, total_titles DESC
LIMIT 15;


-- ==============================================================================
-- QUERY 13: Content Maturity Rating Evolution Across Decades
-- Business Problem:
--   Measure the demographic targeting shift across release decades (1970s-2020s)
--   by grouping ratings into Adult, Teen, Older Kids, and Family cohorts.
-- ==============================================================================
WITH decade_ratings AS (
    SELECT
        (release_year / 10) * 10 || 's' AS release_decade,
        (release_year / 10) * 10 AS decade_int,
        rating,
        CASE
            WHEN rating IN ('TV-MA', 'R', 'NC-17') THEN 'Adult / Mature (TV-MA/R)'
            WHEN rating IN ('TV-14', 'PG-13') THEN 'Teens / Young Adults (TV-14/PG-13)'
            WHEN rating IN ('TV-PG', 'PG') THEN 'Older Kids / Parental Guidance (PG)'
            WHEN rating IN ('TV-Y', 'TV-Y7', 'TV-Y7-FV', 'TV-G', 'G') THEN 'Family & Kids (TV-G/Y)'
            ELSE 'Unrated / Other'
        END AS audience_segment
    FROM titles
    WHERE release_year >= 1970 AND rating IS NOT NULL
),
decade_totals AS (
    SELECT
        release_decade,
        decade_int,
        COUNT(*) AS total_decade_titles,
        SUM(CASE WHEN audience_segment = 'Adult / Mature (TV-MA/R)' THEN 1 ELSE 0 END) AS adult_titles,
        SUM(CASE WHEN audience_segment = 'Teens / Young Adults (TV-14/PG-13)' THEN 1 ELSE 0 END) AS teen_titles,
        SUM(CASE WHEN audience_segment = 'Older Kids / Parental Guidance (PG)' THEN 1 ELSE 0 END) AS older_kids_titles,
        SUM(CASE WHEN audience_segment = 'Family & Kids (TV-G/Y)' THEN 1 ELSE 0 END) AS family_titles,
        SUM(CASE WHEN audience_segment = 'Unrated / Other' THEN 1 ELSE 0 END) AS other_titles
    FROM decade_ratings
    GROUP BY release_decade, decade_int
)
SELECT
    release_decade,
    total_decade_titles,
    adult_titles,
    ROUND((adult_titles * 100.0) / total_decade_titles, 1) AS adult_pct,
    teen_titles,
    ROUND((teen_titles * 100.0) / total_decade_titles, 1) AS teen_pct,
    older_kids_titles,
    ROUND((older_kids_titles * 100.0) / total_decade_titles, 1) AS older_kids_pct,
    family_titles,
    ROUND((family_titles * 100.0) / total_decade_titles, 1) AS family_pct
FROM decade_totals
ORDER BY decade_int ASC;


-- ==============================================================================
-- QUERY 14: Cross-Country Production Breadth & International Collaboration Stance
-- Business Problem:
--   Quantify each nation's domestic production focus versus international co-production
--   collaboration rate (countries with at least 40 titles in catalog).
-- ==============================================================================
WITH title_country_counts AS (
    SELECT
        show_id,
        COUNT(DISTINCT country_id) AS country_count
    FROM title_countries
    GROUP BY show_id
),
country_production_breakdown AS (
    SELECT
        c.country_name,
        COUNT(DISTINCT tc.show_id) AS total_country_titles,
        COUNT(DISTINCT CASE WHEN tcc.country_count = 1 THEN tc.show_id END) AS solo_productions,
        COUNT(DISTINCT CASE WHEN tcc.country_count > 1 THEN tc.show_id END) AS co_productions
    FROM countries c
    JOIN title_countries tc ON c.country_id = tc.country_id
    JOIN title_country_counts tcc ON tc.show_id = tcc.show_id
    GROUP BY c.country_id, c.country_name
    HAVING COUNT(DISTINCT tc.show_id) >= 40
)
SELECT
    country_name,
    total_country_titles,
    solo_productions,
    co_productions,
    ROUND((co_productions * 100.0) / total_country_titles, 1) AS international_collab_rate_pct,
    CASE
        WHEN (co_productions * 100.0) / total_country_titles >= 40.0 THEN 'High Global Integrator (>=40%)'
        WHEN (co_productions * 100.0) / total_country_titles BETWEEN 20.0 AND 39.9 THEN 'Moderate Partner (20-40%)'
        ELSE 'Primarily Domestic / Self-Sustaining (<20%)'
    END AS collaboration_stance
FROM country_production_breakdown
ORDER BY international_collab_rate_pct DESC, total_country_titles DESC;


-- ==============================================================================
-- QUERY 15: Executive Catalog Health & Performance Scorecard
-- Business Problem:
--   Synthesize an executive KPI scorecard summarizing catalog volume, category
--   shares, average runtimes/seasons, average vintage, recent intake velocity,
--   top maturity rating, and primary geographic production hub.
-- ==============================================================================
WITH base_by_type AS (
    SELECT
        type AS segment,
        COUNT(*) AS total_titles,
        ROUND(AVG(duration_int), 1) || ' ' || CASE WHEN type = 'Movie' THEN 'min' ELSE 'seasons' END AS avg_duration,
        ROUND(AVG(release_year), 1) AS avg_release_year,
        ROUND(AVG(CASE WHEN date_added IS NOT NULL THEN CAST(strftime('%Y', date_added) AS INTEGER) - release_year END), 1) AS avg_years_to_stream,
        ROUND(100.0 * SUM(CASE WHEN CAST(strftime('%Y', date_added) AS INTEGER) >= 2019 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_added_recent_wave
    FROM titles
    GROUP BY type
),
overall_base AS (
    SELECT
        'All Catalog' AS segment,
        COUNT(*) AS total_titles,
        'N/A (Multi-Unit)' AS avg_duration,
        ROUND(AVG(release_year), 1) AS avg_release_year,
        ROUND(AVG(CASE WHEN date_added IS NOT NULL THEN CAST(strftime('%Y', date_added) AS INTEGER) - release_year END), 1) AS avg_years_to_stream,
        ROUND(100.0 * SUM(CASE WHEN CAST(strftime('%Y', date_added) AS INTEGER) >= 2019 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_added_recent_wave
    FROM titles
),
combined_metrics AS (
    SELECT * FROM base_by_type
    UNION ALL
    SELECT * FROM overall_base
),
dominant_ratings AS (
    SELECT
        type AS segment,
        rating,
        COUNT(*) AS rating_count,
        ROW_NUMBER() OVER (PARTITION BY type ORDER BY COUNT(*) DESC) AS rn
    FROM titles
    WHERE rating IS NOT NULL
    GROUP BY type, rating
    UNION ALL
    SELECT
        'All Catalog' AS segment,
        rating,
        COUNT(*) AS rating_count,
        ROW_NUMBER() OVER (PARTITION BY 'All Catalog' ORDER BY COUNT(*) DESC) AS rn
    FROM titles
    WHERE rating IS NOT NULL
    GROUP BY rating
),
dominant_countries AS (
    SELECT
        t.type AS segment,
        c.country_name,
        COUNT(*) AS country_count,
        ROW_NUMBER() OVER (PARTITION BY t.type ORDER BY COUNT(*) DESC) AS rn
    FROM titles t
    JOIN title_countries tc ON t.show_id = tc.show_id
    JOIN countries c ON tc.country_id = c.country_id
    GROUP BY t.type, c.country_name
    UNION ALL
    SELECT
        'All Catalog' AS segment,
        c.country_name,
        COUNT(*) AS country_count,
        ROW_NUMBER() OVER (PARTITION BY 'All Catalog' ORDER BY COUNT(*) DESC) AS rn
    FROM titles t
    JOIN title_countries tc ON t.show_id = tc.show_id
    JOIN countries c ON tc.country_id = c.country_id
    GROUP BY c.country_name
)
SELECT
    m.segment,
    m.total_titles,
    ROUND((m.total_titles * 100.0) / (SELECT COUNT(*) FROM titles), 1) AS catalog_share_pct,
    m.avg_duration,
    m.avg_release_year,
    m.avg_years_to_stream AS avg_acquisition_latency_yrs,
    m.pct_added_recent_wave AS pct_added_2019_2021,
    dr.rating AS top_rating,
    dc.country_name AS top_origin_country
FROM combined_metrics m
LEFT JOIN dominant_ratings dr ON m.segment = dr.segment AND dr.rn = 1
LEFT JOIN dominant_countries dc ON m.segment = dc.segment AND dc.rn = 1
ORDER BY m.total_titles DESC;
