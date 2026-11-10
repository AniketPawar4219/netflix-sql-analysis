-- ==============================================================================
-- Netflix Data Analysis Project: 01_schema_ddl.sql
-- Description: Third Normal Form (3NF) relational database schema for Netflix
--              Movies & TV Shows dataset, with full referential integrity and indexes.
-- Target Engine: SQLite 3 / DuckDB compatible
-- ==============================================================================

PRAGMA foreign_keys = ON;

-- ------------------------------------------------------------------------------
-- 1. Raw / Staging Table (Retains original denormalized format for staging & audit)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS netflix_raw;
CREATE TABLE netflix_raw (
    show_id TEXT PRIMARY KEY,
    type TEXT,
    title TEXT,
    director TEXT,
    cast TEXT,
    country TEXT,
    date_added TEXT,
    date_added_clean DATE,
    release_year INTEGER,
    rating TEXT,
    duration TEXT,
    duration_int INTEGER,
    duration_unit TEXT,
    listed_in TEXT,
    description TEXT
);

-- ------------------------------------------------------------------------------
-- 2. Core Entity Table: Titles
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS titles;
CREATE TABLE titles (
    show_id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('Movie', 'TV Show')),
    title TEXT NOT NULL,
    date_added DATE,
    release_year INTEGER NOT NULL,
    rating TEXT,
    duration TEXT,
    duration_int INTEGER,
    duration_unit TEXT,
    description TEXT
);

-- ------------------------------------------------------------------------------
-- 3. Dimension Tables
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS directors;
CREATE TABLE directors (
    director_id INTEGER PRIMARY KEY AUTOINCREMENT,
    director_name TEXT UNIQUE NOT NULL
);

DROP TABLE IF EXISTS actors;
CREATE TABLE actors (
    actor_id INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_name TEXT UNIQUE NOT NULL
);

DROP TABLE IF EXISTS genres;
CREATE TABLE genres (
    genre_id INTEGER PRIMARY KEY AUTOINCREMENT,
    genre_name TEXT UNIQUE NOT NULL
);

DROP TABLE IF EXISTS countries;
CREATE TABLE countries (
    country_id INTEGER PRIMARY KEY AUTOINCREMENT,
    country_name TEXT UNIQUE NOT NULL
);

-- ------------------------------------------------------------------------------
-- 4. Junction / Bridge Tables (Resolving Many-to-Many Relationships)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS title_directors;
CREATE TABLE title_directors (
    show_id TEXT NOT NULL,
    director_id INTEGER NOT NULL,
    PRIMARY KEY (show_id, director_id),
    FOREIGN KEY (show_id) REFERENCES titles (show_id) ON DELETE CASCADE,
    FOREIGN KEY (director_id) REFERENCES directors (director_id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS title_actors;
CREATE TABLE title_actors (
    show_id TEXT NOT NULL,
    actor_id INTEGER NOT NULL,
    PRIMARY KEY (show_id, actor_id),
    FOREIGN KEY (show_id) REFERENCES titles (show_id) ON DELETE CASCADE,
    FOREIGN KEY (actor_id) REFERENCES actors (actor_id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS title_genres;
CREATE TABLE title_genres (
    show_id TEXT NOT NULL,
    genre_id INTEGER NOT NULL,
    PRIMARY KEY (show_id, genre_id),
    FOREIGN KEY (show_id) REFERENCES titles (show_id) ON DELETE CASCADE,
    FOREIGN KEY (genre_id) REFERENCES genres (genre_id) ON DELETE CASCADE
);

DROP TABLE IF EXISTS title_countries;
CREATE TABLE title_countries (
    show_id TEXT NOT NULL,
    country_id INTEGER NOT NULL,
    PRIMARY KEY (show_id, country_id),
    FOREIGN KEY (show_id) REFERENCES titles (show_id) ON DELETE CASCADE,
    FOREIGN KEY (country_id) REFERENCES countries (country_id) ON DELETE CASCADE
);

-- ------------------------------------------------------------------------------
-- 5. Performance Indexes
-- ------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_titles_type ON titles(type);
CREATE INDEX IF NOT EXISTS idx_titles_date_added ON titles(date_added);
CREATE INDEX IF NOT EXISTS idx_titles_release_year ON titles(release_year);
CREATE INDEX IF NOT EXISTS idx_titles_rating ON titles(rating);
CREATE INDEX IF NOT EXISTS idx_title_directors_dir ON title_directors(director_id);
CREATE INDEX IF NOT EXISTS idx_title_actors_act ON title_actors(actor_id);
CREATE INDEX IF NOT EXISTS idx_title_genres_gen ON title_genres(genre_id);
CREATE INDEX IF NOT EXISTS idx_title_countries_cou ON title_countries(country_id);
