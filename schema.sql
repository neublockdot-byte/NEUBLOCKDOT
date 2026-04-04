-- ==============================================================
-- NEUBLOCK V13 — Production SQL Schema
-- Supabase Project: dqjzvembtenfhtgpttie
-- Project URL: https://dqjzvembtenfhtgpttie.supabase.co
--
-- HOW TO USE:
--   1. Open Supabase Dashboard → SQL Editor
--   2. Paste this entire file and click RUN
--   3. Fully idempotent — safe to re-run at any time
-- ==============================================================


-- ==============================================================
-- SECTION 0 — EXTENSIONS
-- ==============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";


-- ==============================================================
-- SECTION 1 — SAFE CLEANUP (handles fresh DB with no tables yet)
-- ==============================================================

-- Drop triggers safely — won't error if tables don't exist yet
DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_stats_projects   ON projects;
  DROP TRIGGER IF EXISTS trg_stats_components ON components;
  DROP TRIGGER IF EXISTS trg_stats_circuits   ON circuits;
  DROP TRIGGER IF EXISTS trg_stats_courses    ON courses;
EXCEPTION WHEN undefined_table THEN NULL; END $$;

DO $$ BEGIN
  DROP TRIGGER IF EXISTS trg_updated_projects   ON projects;
  DROP TRIGGER IF EXISTS trg_updated_components ON components;
  DROP TRIGGER IF EXISTS trg_updated_circuits   ON circuits;
  DROP TRIGGER IF EXISTS trg_updated_courses    ON courses;
EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- Drop functions
DROP FUNCTION IF EXISTS refresh_nb_stats() CASCADE;
DROP FUNCTION IF EXISTS set_updated_at()   CASCADE;

-- Drop ALL existing RLS policies (safe on fresh DB)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT policyname, tablename
    FROM   pg_policies
    WHERE  tablename IN ('projects','components','circuits','courses','nb_stats')
      AND  schemaname = 'public'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', r.policyname, r.tablename);
  END LOOP;
END $$;


-- ==============================================================
-- SECTION 2 — TABLES
-- ==============================================================

-- 2.1  projects
CREATE TABLE IF NOT EXISTS projects (
  id          uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  title       text        NOT NULL
                          CONSTRAINT chk_projects_title
                          CHECK (char_length(title) BETWEEN 1 AND 200),
  description text
                          CONSTRAINT chk_projects_desc
                          CHECK (description IS NULL OR char_length(description) <= 5000),
  tech        text[]      NOT NULL DEFAULT '{}',
  icon        text        NOT NULL DEFAULT 'fa-robot'
                          CONSTRAINT chk_projects_icon
                          CHECK (icon ~ '^fa-[a-z0-9-]+$'),
  github      text        CONSTRAINT chk_projects_github  CHECK (github IS NULL OR github ~* '^https?://'),
  link        text        CONSTRAINT chk_projects_link    CHECK (link   IS NULL OR link   ~* '^https?://'),
  video       text        CONSTRAINT chk_projects_video   CHECK (video  IS NULL OR video  ~* '^https?://'),
  images      text[]      NOT NULL DEFAULT '{}',
  code_files  jsonb       NOT NULL DEFAULT '[]',
  components  jsonb       NOT NULL DEFAULT '[]',
  build_steps text[]      NOT NULL DEFAULT '{}',
  videos      jsonb       NOT NULL DEFAULT '[]',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- 2.2  components
CREATE TABLE IF NOT EXISTS components (
  id             uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name           text        NOT NULL
                             CONSTRAINT chk_components_name
                             CHECK (char_length(name) BETWEEN 1 AND 200),
  category       text        CONSTRAINT chk_components_cat   CHECK (category IS NULL OR char_length(category) <= 100),
  description    text        CONSTRAINT chk_components_desc  CHECK (description IS NULL OR char_length(description) <= 5000),
  manufacturer   text        CONSTRAINT chk_components_mfr   CHECK (manufacturer IS NULL OR char_length(manufacturer) <= 200),
  datasheet      text        CONSTRAINT chk_components_ds    CHECK (datasheet IS NULL OR datasheet ~* '^https?://'),
  image          text        CONSTRAINT chk_components_img   CHECK (image IS NULL OR image ~* '^https?://'),
  pinout         text        CONSTRAINT chk_components_pin   CHECK (pinout IS NULL OR pinout ~* '^https?://'),
  specifications text        CONSTRAINT chk_components_specs CHECK (specifications IS NULL OR char_length(specifications) <= 2000),
  price          text        CONSTRAINT chk_components_price CHECK (price IS NULL OR char_length(price) <= 50),
  quantity       text        NOT NULL DEFAULT '0',
  tags           text[]      NOT NULL DEFAULT '{}',
  notes          text        CONSTRAINT chk_components_notes CHECK (notes IS NULL OR char_length(notes) <= 5000),
  videos         jsonb       NOT NULL DEFAULT '[]',
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

-- 2.3  circuits
CREATE TABLE IF NOT EXISTS circuits (
  id              uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            text        NOT NULL
                              CONSTRAINT chk_circuits_name
                              CHECK (char_length(name) BETWEEN 1 AND 200),
  description     text        CONSTRAINT chk_circuits_desc  CHECK (description IS NULL OR char_length(description) <= 5000),
  image           text        CONSTRAINT chk_circuits_image CHECK (image IS NULL OR image ~* '^https?://'),
  pdf             text        CONSTRAINT chk_circuits_pdf   CHECK (pdf IS NULL OR pdf ~* '^https?://'),
  code            text        CONSTRAINT chk_circuits_code  CHECK (code IS NULL OR code ~* '^https?://'),
  difficulty      text        CONSTRAINT chk_circuits_diff
                              CHECK (difficulty IS NULL OR difficulty IN ('Beginner','Intermediate','Advanced')),
  components_used jsonb       NOT NULL DEFAULT '[]',
  notes           text        CONSTRAINT chk_circuits_notes CHECK (notes IS NULL OR char_length(notes) <= 5000),
  videos          jsonb       NOT NULL DEFAULT '[]',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- 2.4  courses
CREATE TABLE IF NOT EXISTS courses (
  id          uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
  title       text        NOT NULL
                          CONSTRAINT chk_courses_title
                          CHECK (char_length(title) BETWEEN 1 AND 200),
  description text        CONSTRAINT chk_courses_desc  CHECK (description IS NULL OR char_length(description) <= 5000),
  category    text        NOT NULL DEFAULT 'arduino'
                          CONSTRAINT chk_courses_cat
                          CHECK (category IN ('arduino','robotics','ai','python')),
  level       text        NOT NULL DEFAULT 'Beginner'
                          CONSTRAINT chk_courses_level
                          CHECK (level IN ('Beginner','Intermediate','Advanced')),
  thumbnail   text        CONSTRAINT chk_courses_thumb CHECK (thumbnail IS NULL OR thumbnail ~* '^https?://'),
  is_free     boolean     NOT NULL DEFAULT true,
  price       text        NOT NULL DEFAULT '0'
                          CONSTRAINT chk_courses_price CHECK (char_length(price) <= 50),
  videos      jsonb       NOT NULL DEFAULT '[]',
  lessons     jsonb       NOT NULL DEFAULT '[]',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- 2.5  nb_stats (single-row cache — PRIMARY KEY enforces exactly one row)
CREATE TABLE IF NOT EXISTS nb_stats (
  singleton        boolean     PRIMARY KEY DEFAULT true
                               CONSTRAINT chk_nb_stats_one_row CHECK (singleton = true),
  total_projects   integer     NOT NULL DEFAULT 0,
  total_components integer     NOT NULL DEFAULT 0,
  total_circuits   integer     NOT NULL DEFAULT 0,
  total_courses    integer     NOT NULL DEFAULT 0,
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- Seed the single row (safe to re-run)
INSERT INTO nb_stats (singleton, total_projects, total_components, total_circuits, total_courses)
VALUES (true, 0, 0, 0, 0)
ON CONFLICT (singleton) DO NOTHING;


-- ==============================================================
-- SECTION 3 — INDEXES
-- ==============================================================

-- B-tree for ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_projects_created_at   ON projects   (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_components_created_at ON components (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_circuits_created_at   ON circuits   (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_courses_created_at    ON courses    (created_at DESC);

-- B-tree for equality filters
CREATE INDEX IF NOT EXISTS idx_components_category ON components (category);
CREATE INDEX IF NOT EXISTS idx_circuits_difficulty ON circuits   (difficulty);
CREATE INDEX IF NOT EXISTS idx_courses_category    ON courses    (category);
CREATE INDEX IF NOT EXISTS idx_courses_is_free     ON courses    (is_free);

-- GIN trigram for fast search boxes
CREATE INDEX IF NOT EXISTS idx_projects_title_trgm  ON projects   USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_components_name_trgm ON components USING gin (name  gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_circuits_name_trgm   ON circuits   USING gin (name  gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_courses_title_trgm   ON courses    USING gin (title gin_trgm_ops);


-- ==============================================================
-- SECTION 4 — updated_at AUTO-STAMP TRIGGER
-- ==============================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_updated_projects   BEFORE UPDATE ON projects   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_updated_components BEFORE UPDATE ON components FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_updated_circuits   BEFORE UPDATE ON circuits   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_updated_courses    BEFORE UPDATE ON courses    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ==============================================================
-- SECTION 5 — nb_stats AUTO-REFRESH TRIGGER
-- ==============================================================

CREATE OR REPLACE FUNCTION refresh_nb_stats()
RETURNS TRIGGER LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO nb_stats (singleton, total_projects, total_components, total_circuits, total_courses, updated_at)
  VALUES (
    true,
    (SELECT COUNT(*) FROM projects),
    (SELECT COUNT(*) FROM components),
    (SELECT COUNT(*) FROM circuits),
    (SELECT COUNT(*) FROM courses),
    now()
  )
  ON CONFLICT (singleton) DO UPDATE SET
    total_projects   = (SELECT COUNT(*) FROM projects),
    total_components = (SELECT COUNT(*) FROM components),
    total_circuits   = (SELECT COUNT(*) FROM circuits),
    total_courses    = (SELECT COUNT(*) FROM courses),
    updated_at       = now();
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_stats_projects   AFTER INSERT OR DELETE ON projects   FOR EACH STATEMENT EXECUTE FUNCTION refresh_nb_stats();
CREATE TRIGGER trg_stats_components AFTER INSERT OR DELETE ON components FOR EACH STATEMENT EXECUTE FUNCTION refresh_nb_stats();
CREATE TRIGGER trg_stats_circuits   AFTER INSERT OR DELETE ON circuits   FOR EACH STATEMENT EXECUTE FUNCTION refresh_nb_stats();
CREATE TRIGGER trg_stats_courses    AFTER INSERT OR DELETE ON courses    FOR EACH STATEMENT EXECUTE FUNCTION refresh_nb_stats();

-- Sync stats immediately
SELECT refresh_nb_stats();


-- ==============================================================
-- SECTION 6 — ROW LEVEL SECURITY
-- ==============================================================

ALTER TABLE projects   ENABLE ROW LEVEL SECURITY;
ALTER TABLE components ENABLE ROW LEVEL SECURITY;
ALTER TABLE circuits   ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses    ENABLE ROW LEVEL SECURITY;
ALTER TABLE nb_stats   ENABLE ROW LEVEL SECURITY;

-- projects
CREATE POLICY "projects_select_public" ON projects FOR SELECT USING (true);
CREATE POLICY "projects_insert_auth"   ON projects FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "projects_update_auth"   ON projects FOR UPDATE USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "projects_delete_auth"   ON projects FOR DELETE USING (auth.uid() IS NOT NULL);

-- components
CREATE POLICY "components_select_public" ON components FOR SELECT USING (true);
CREATE POLICY "components_insert_auth"   ON components FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "components_update_auth"   ON components FOR UPDATE USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "components_delete_auth"   ON components FOR DELETE USING (auth.uid() IS NOT NULL);

-- circuits
CREATE POLICY "circuits_select_public" ON circuits FOR SELECT USING (true);
CREATE POLICY "circuits_insert_auth"   ON circuits FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "circuits_update_auth"   ON circuits FOR UPDATE USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "circuits_delete_auth"   ON circuits FOR DELETE USING (auth.uid() IS NOT NULL);

-- courses
CREATE POLICY "courses_select_public" ON courses FOR SELECT USING (true);
CREATE POLICY "courses_insert_auth"   ON courses FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "courses_update_auth"   ON courses FOR UPDATE USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "courses_delete_auth"   ON courses FOR DELETE USING (auth.uid() IS NOT NULL);

-- nb_stats — public read, NO direct writes (trigger handles all updates)
CREATE POLICY "nb_stats_select_public"       ON nb_stats FOR SELECT USING (true);
CREATE POLICY "nb_stats_block_direct_writes" ON nb_stats FOR ALL   USING (false) WITH CHECK (false);


-- ==============================================================
-- SECTION 7 — ROLE GRANTS
-- ==============================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT ON projects, components, circuits, courses, nb_stats TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON projects, components, circuits, courses TO authenticated;
GRANT SELECT ON nb_stats TO authenticated;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;


-- ==============================================================
-- SECTION 8 — HELPER VIEW
-- ==============================================================

CREATE OR REPLACE VIEW v_content_summary AS
  SELECT 'projects'   AS content_type, COUNT(*) AS total FROM projects UNION ALL
  SELECT 'components', COUNT(*) FROM components UNION ALL
  SELECT 'circuits',   COUNT(*) FROM circuits   UNION ALL
  SELECT 'courses',    COUNT(*) FROM courses;


-- ==============================================================
-- SECTION 9 — VERIFICATION (run these after setup to confirm)
-- ==============================================================

-- Tables:   SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY 1;
-- RLS:      SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public';
-- Policies: SELECT tablename, policyname, cmd FROM pg_policies WHERE schemaname='public' ORDER BY 1,2;
-- Triggers: SELECT trigger_name, event_object_table FROM information_schema.triggers WHERE trigger_schema='public';
-- Indexes:  SELECT indexname, tablename FROM pg_indexes WHERE schemaname='public' ORDER BY 2;
-- Stats:    SELECT * FROM nb_stats;
-- Counts:   SELECT * FROM v_content_summary;


-- ==============================================================
-- END — NEUBLOCK V13 Schema ready.
-- ==============================================================
