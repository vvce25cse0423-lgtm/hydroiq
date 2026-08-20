-- ============================================================
-- HydroIQ Supabase Database Schema
-- Run this entire file in the Supabase SQL Editor
-- Dashboard → SQL Editor → New Query → Paste → Run
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── USERS TABLE ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.users (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT NOT NULL,
  name          TEXT NOT NULL DEFAULT '',
  gender        TEXT NOT NULL DEFAULT 'male' CHECK (gender IN ('male', 'female', 'other')),
  age           INTEGER NOT NULL DEFAULT 25 CHECK (age > 0 AND age < 150),
  weight_kg     NUMERIC(5,2) NOT NULL DEFAULT 70.0 CHECK (weight_kg > 0),
  daily_goal_ml INTEGER NOT NULL DEFAULT 2000 CHECK (daily_goal_ml > 0),
  avatar_url    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── HYDRATION LOGS ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hydration_logs (
  id         TEXT PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount_ml  INTEGER NOT NULL CHECK (amount_ml > 0),
  logged_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  note       TEXT
);

-- ─── STEP LOGS ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.step_logs (
  id               TEXT PRIMARY KEY,
  user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  steps            INTEGER NOT NULL DEFAULT 0 CHECK (steps >= 0),
  distance_km      NUMERIC(8,3) NOT NULL DEFAULT 0,
  calories_burned  NUMERIC(8,2) NOT NULL DEFAULT 0,
  date             DATE NOT NULL DEFAULT CURRENT_DATE,
  UNIQUE (user_id, date)
);

-- ─── SLEEP LOGS ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sleep_logs (
  id              TEXT PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sleep_start     TIMESTAMPTZ NOT NULL,
  sleep_end       TIMESTAMPTZ NOT NULL,
  duration_hours  NUMERIC(4,2) NOT NULL DEFAULT 0,
  sleep_score     INTEGER NOT NULL DEFAULT 0 CHECK (sleep_score >= 0 AND sleep_score <= 100),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── AI CHATS ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_chats (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  messages   JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

-- ─── SETTINGS ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.settings (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id              UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  notif_enabled        BOOLEAN NOT NULL DEFAULT TRUE,
  reminder_interval_h  INTEGER NOT NULL DEFAULT 2,
  dark_mode            BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

-- ─── INDEXES ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_hydration_logs_user_date
  ON public.hydration_logs (user_id, logged_at DESC);

CREATE INDEX IF NOT EXISTS idx_step_logs_user_date
  ON public.step_logs (user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_sleep_logs_user_date
  ON public.sleep_logs (user_id, sleep_start DESC);

-- ─── ROW LEVEL SECURITY (RLS) ─────────────────────────────────────────────────

-- Enable RLS on all tables
ALTER TABLE public.users           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hydration_logs  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.step_logs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sleep_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_chats        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings        ENABLE ROW LEVEL SECURITY;

-- ── users policies ──
CREATE POLICY "Users can view own profile"
  ON public.users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON public.users FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON public.users FOR UPDATE
  USING (auth.uid() = id);

-- ── hydration_logs policies ──
CREATE POLICY "Users manage own hydration logs"
  ON public.hydration_logs FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── step_logs policies ──
CREATE POLICY "Users manage own step logs"
  ON public.step_logs FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── sleep_logs policies ──
CREATE POLICY "Users manage own sleep logs"
  ON public.sleep_logs FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── ai_chats policies ──
CREATE POLICY "Users manage own chats"
  ON public.ai_chats FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── settings policies ──
CREATE POLICY "Users manage own settings"
  ON public.settings FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ─── TRIGGER: auto-update updated_at ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER set_settings_updated_at
  BEFORE UPDATE ON public.settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ─── DONE ─────────────────────────────────────────────────────────────────────
-- Your HydroIQ database is ready!
-- Next: update lib/core/constants/app_constants.dart with your Supabase URL and anon key.
