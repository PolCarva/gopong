-- ============================================
-- SISTEMA SIMPLE DE PUNTOS
-- 1 partido ganado = +1 punto
-- 1 partido perdido = -1 punto
-- ============================================

-- Eliminar funciones existentes si existen
DROP FUNCTION IF EXISTS add_match_simple CASCADE;
DROP FUNCTION IF EXISTS edit_match_simple CASCADE;
DROP FUNCTION IF EXISTS delete_match_simple CASCADE;

-- Eliminar tablas existentes si existen
DROP TABLE IF EXISTS matches CASCADE;
DROP TABLE IF EXISTS players CASCADE;

-- ============================================
-- CREAR TABLA DE JUGADORES
-- ============================================
CREATE TABLE players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  points INTEGER NOT NULL DEFAULT 0,
  wins INTEGER NOT NULL DEFAULT 0,
  losses INTEGER NOT NULL DEFAULT 0,
  current_streak INTEGER NOT NULL DEFAULT 0,
  max_streak INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================
-- CREAR TABLA DE PARTIDOS
-- ============================================
CREATE TABLE matches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player1_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  player2_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  winner_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  played_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT different_players CHECK (player1_id != player2_id),
  CONSTRAINT valid_winner CHECK (winner_id = player1_id OR winner_id = player2_id)
);

-- Índices para mejorar el rendimiento
CREATE INDEX idx_matches_player1 ON matches(player1_id);
CREATE INDEX idx_matches_player2 ON matches(player2_id);
CREATE INDEX idx_matches_winner ON matches(winner_id);
CREATE INDEX idx_matches_played_at ON matches(played_at DESC);

-- ============================================
-- FUNCIÓN: AGREGAR PARTIDO
-- ============================================
CREATE OR REPLACE FUNCTION add_match_simple(
  p_player1_id UUID,
  p_player2_id UUID,
  p_winner_id UUID
)
RETURNS UUID AS $$
DECLARE
  v_match_id UUID;
  v_loser_id UUID;
  v_winner_current_streak INTEGER;
  v_loser_current_streak INTEGER;
BEGIN
  -- Validar que los jugadores sean diferentes
  IF p_player1_id = p_player2_id THEN
    RAISE EXCEPTION 'Los jugadores deben ser diferentes';
  END IF;

  -- Validar que el ganador sea uno de los jugadores
  IF p_winner_id != p_player1_id AND p_winner_id != p_player2_id THEN
    RAISE EXCEPTION 'El ganador debe ser uno de los jugadores del partido';
  END IF;

  -- Determinar el perdedor
  v_loser_id := CASE 
    WHEN p_winner_id = p_player1_id THEN p_player2_id 
    ELSE p_player1_id 
  END;

  -- Insertar el partido
  INSERT INTO matches (player1_id, player2_id, winner_id)
  VALUES (p_player1_id, p_player2_id, p_winner_id)
  RETURNING id INTO v_match_id;

  -- Obtener rachas actuales
  SELECT current_streak INTO v_winner_current_streak FROM players WHERE id = p_winner_id;
  SELECT current_streak INTO v_loser_current_streak FROM players WHERE id = v_loser_id;

  -- Actualizar estadísticas del GANADOR
  -- +1 punto, +1 victoria, racha aumenta (si es positiva) o se reinicia a 1
  UPDATE players
  SET 
    points = points + 1,
    wins = wins + 1,
    current_streak = CASE 
      WHEN v_winner_current_streak >= 0 THEN v_winner_current_streak + 1
      ELSE 1
    END,
    max_streak = GREATEST(
      max_streak,
      CASE 
        WHEN v_winner_current_streak >= 0 THEN v_winner_current_streak + 1
        ELSE 1
      END
    )
  WHERE id = p_winner_id;

  -- Actualizar estadísticas del PERDEDOR
  -- -1 punto, +1 derrota, racha disminuye (si es negativa) o se reinicia a -1
  UPDATE players
  SET 
    points = points - 1,
    losses = losses + 1,
    current_streak = CASE 
      WHEN v_loser_current_streak <= 0 THEN v_loser_current_streak - 1
      ELSE -1
    END
  WHERE id = v_loser_id;

  RETURN v_match_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- FUNCIÓN: EDITAR PARTIDO
-- ============================================
CREATE OR REPLACE FUNCTION edit_match_simple(
  p_match_id UUID,
  p_new_winner_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_old_winner_id UUID;
  v_player1_id UUID;
  v_player2_id UUID;
  v_old_loser_id UUID;
  v_new_loser_id UUID;
BEGIN
  -- Obtener información del partido actual
  SELECT player1_id, player2_id, winner_id
  INTO v_player1_id, v_player2_id, v_old_winner_id
  FROM matches
  WHERE id = p_match_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Partido no encontrado';
  END IF;

  -- Si el ganador no cambió, no hacer nada
  IF v_old_winner_id = p_new_winner_id THEN
    RETURN;
  END IF;

  -- Validar que el nuevo ganador sea uno de los jugadores
  IF p_new_winner_id != v_player1_id AND p_new_winner_id != v_player2_id THEN
    RAISE EXCEPTION 'El ganador debe ser uno de los jugadores del partido';
  END IF;

  -- Determinar perdedores
  v_old_loser_id := CASE 
    WHEN v_old_winner_id = v_player1_id THEN v_player2_id 
    ELSE v_player1_id 
  END;
  
  v_new_loser_id := CASE 
    WHEN p_new_winner_id = v_player1_id THEN v_player2_id 
    ELSE v_player1_id 
  END;

  -- REVERTIR cambios del ganador anterior
  -- -1 punto, -1 victoria
  UPDATE players
  SET 
    points = points - 1,
    wins = wins - 1
  WHERE id = v_old_winner_id;

  -- REVERTIR cambios del perdedor anterior
  -- +1 punto, -1 derrota
  UPDATE players
  SET 
    points = points + 1,
    losses = losses - 1
  WHERE id = v_old_loser_id;

  -- APLICAR cambios al nuevo ganador
  -- +1 punto, +1 victoria
  UPDATE players
  SET 
    points = points + 1,
    wins = wins + 1
  WHERE id = p_new_winner_id;

  -- APLICAR cambios al nuevo perdedor
  -- -1 punto, +1 derrota
  UPDATE players
  SET 
    points = points - 1,
    losses = losses + 1
  WHERE id = v_new_loser_id;

  -- Actualizar el partido
  UPDATE matches
  SET winner_id = p_new_winner_id
  WHERE id = p_match_id;

  -- Recalcular rachas para ambos jugadores
  PERFORM recalculate_streaks(v_player1_id);
  PERFORM recalculate_streaks(v_player2_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- FUNCIÓN: ELIMINAR PARTIDO
-- ============================================
CREATE OR REPLACE FUNCTION delete_match_simple(
  p_match_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_winner_id UUID;
  v_loser_id UUID;
  v_player1_id UUID;
  v_player2_id UUID;
BEGIN
  -- Obtener información del partido
  SELECT player1_id, player2_id, winner_id
  INTO v_player1_id, v_player2_id, v_winner_id
  FROM matches
  WHERE id = p_match_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Partido no encontrado';
  END IF;

  -- Determinar el perdedor
  v_loser_id := CASE 
    WHEN v_winner_id = v_player1_id THEN v_player2_id 
    ELSE v_player1_id 
  END;

  -- REVERTIR cambios del ganador
  -- -1 punto, -1 victoria
  UPDATE players
  SET 
    points = points - 1,
    wins = wins - 1
  WHERE id = v_winner_id;

  -- REVERTIR cambios del perdedor
  -- +1 punto, -1 derrota
  UPDATE players
  SET 
    points = points + 1,
    losses = losses - 1
  WHERE id = v_loser_id;

  -- Eliminar el partido
  DELETE FROM matches WHERE id = p_match_id;

  -- Recalcular rachas para ambos jugadores
  PERFORM recalculate_streaks(v_player1_id);
  PERFORM recalculate_streaks(v_player2_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- FUNCIÓN: RECALCULAR RACHAS
-- ============================================
CREATE OR REPLACE FUNCTION recalculate_streaks(p_player_id UUID)
RETURNS VOID AS $$
DECLARE
  v_current_streak INTEGER := 0;
  v_max_streak INTEGER := 0;
  v_match RECORD;
BEGIN
  -- Recorrer todos los partidos del jugador en orden cronológico
  FOR v_match IN
    SELECT winner_id, played_at
    FROM matches
    WHERE player1_id = p_player_id OR player2_id = p_player_id
    ORDER BY played_at ASC
  LOOP
    IF v_match.winner_id = p_player_id THEN
      -- Ganó: aumentar racha positiva o reiniciar a 1
      IF v_current_streak >= 0 THEN
        v_current_streak := v_current_streak + 1;
      ELSE
        v_current_streak := 1;
      END IF;
    ELSE
      -- Perdió: aumentar racha negativa o reiniciar a -1
      IF v_current_streak <= 0 THEN
        v_current_streak := v_current_streak - 1;
      ELSE
        v_current_streak := -1;
      END IF;
    END IF;

    -- Actualizar racha máxima
    v_max_streak := GREATEST(v_max_streak, v_current_streak);
  END LOOP;

  -- Actualizar las rachas del jugador
  UPDATE players
  SET 
    current_streak = v_current_streak,
    max_streak = v_max_streak
  WHERE id = p_player_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================
DO $$
BEGIN
  RAISE NOTICE '✅ Sistema simple de puntos creado exitosamente';
  RAISE NOTICE '📊 Tablas: players, matches';
  RAISE NOTICE '⚡ Funciones: add_match_simple, edit_match_simple, delete_match_simple';
  RAISE NOTICE '🎯 Sistema: 1 partido ganado = +1 punto, 1 partido perdido = -1 punto';
END $$;
