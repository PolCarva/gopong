-- Simplificar el sistema: eliminar ELO, volver a sistema de victorias con rachas
-- Este script limpia completamente la base de datos y la reinicia

-- 1. Eliminar todas las funciones ELO existentes
DROP FUNCTION IF EXISTS add_match_with_both_scenarios CASCADE;
DROP FUNCTION IF EXISTS edit_match_with_scenarios CASCADE;
DROP FUNCTION IF EXISTS delete_match_with_scenarios CASCADE;
DROP FUNCTION IF EXISTS add_match_with_elo_changes CASCADE;
DROP FUNCTION IF EXISTS edit_match_with_elo_changes CASCADE;
DROP FUNCTION IF EXISTS delete_match_with_elo_revert CASCADE;
DROP FUNCTION IF EXISTS update_player_elo_simple CASCADE;
DROP FUNCTION IF EXISTS revert_player_elo_simple CASCADE;
DROP FUNCTION IF EXISTS calculate_elo_change CASCADE;
DROP FUNCTION IF EXISTS update_elo_for_match CASCADE;
DROP FUNCTION IF EXISTS revert_elo_for_match CASCADE;

-- 2. Eliminar todos los triggers existentes
DROP TRIGGER IF EXISTS handle_match_update_safe_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_delete_safe_trigger ON matches;
DROP TRIGGER IF EXISTS update_player_stats_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_change_trigger ON matches;

-- 3. Limpiar todos los datos existentes
DELETE FROM matches;
DELETE FROM players;

-- 4. Modificar la tabla players: eliminar ELO, agregar points
ALTER TABLE players DROP COLUMN IF EXISTS elo_rating;
ALTER TABLE players ADD COLUMN IF NOT EXISTS points INTEGER DEFAULT 0;

-- Asegurar que las columnas de racha existan
ALTER TABLE players ADD COLUMN IF NOT EXISTS current_streak INTEGER DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS max_streak INTEGER DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS matches_played INTEGER DEFAULT 0;
ALTER TABLE players ADD COLUMN IF NOT EXISTS matches_won INTEGER DEFAULT 0;

-- 5. Simplificar la tabla matches: eliminar todas las columnas de ELO
ALTER TABLE matches DROP COLUMN IF EXISTS elo_change;
ALTER TABLE matches DROP COLUMN IF EXISTS player1_elo_change;
ALTER TABLE matches DROP COLUMN IF EXISTS player2_elo_change;
ALTER TABLE matches DROP COLUMN IF EXISTS player1_win_elo_change;
ALTER TABLE matches DROP COLUMN IF EXISTS player1_lose_elo_change;
ALTER TABLE matches DROP COLUMN IF EXISTS player2_win_elo_change;
ALTER TABLE matches DROP COLUMN IF EXISTS player2_lose_elo_change;

-- Mantener solo las columnas esenciales
-- id, player1_id, player2_id, winner_id, player1_score, player2_score, created_at

-- 6. Crear función simple para agregar partido
CREATE OR REPLACE FUNCTION add_match_simple(
  p_player1_id INTEGER,
  p_player2_id INTEGER,
  p_winner_id INTEGER,
  p_player1_score INTEGER DEFAULT NULL,
  p_player2_score INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
  v_match_id INTEGER;
  v_loser_id INTEGER;
  v_winner_current_streak INTEGER;
  v_loser_current_streak INTEGER;
BEGIN
  -- Determinar el perdedor
  IF p_winner_id = p_player1_id THEN
    v_loser_id := p_player2_id;
  ELSE
    v_loser_id := p_player1_id;
  END IF;

  -- Insertar el partido
  INSERT INTO matches (player1_id, player2_id, winner_id, player1_score, player2_score)
  VALUES (p_player1_id, p_player2_id, p_winner_id, p_player1_score, p_player2_score)
  RETURNING id INTO v_match_id;

  -- Actualizar estadísticas del ganador
  UPDATE players
  SET 
    matches_played = matches_played + 1,
    matches_won = matches_won + 1,
    points = matches_won + 1, -- points = victorias
    current_streak = current_streak + 1,
    max_streak = GREATEST(max_streak, current_streak + 1)
  WHERE id = p_winner_id;

  -- Actualizar estadísticas del perdedor (resetear racha)
  UPDATE players
  SET 
    matches_played = matches_played + 1,
    current_streak = 0
  WHERE id = v_loser_id;

  RETURN v_match_id;
END;
$$ LANGUAGE plpgsql;

-- 7. Crear función simple para editar partido
CREATE OR REPLACE FUNCTION edit_match_simple(
  p_match_id INTEGER,
  p_new_winner_id INTEGER,
  p_player1_score INTEGER DEFAULT NULL,
  p_player2_score INTEGER DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_old_winner_id INTEGER;
  v_old_loser_id INTEGER;
  v_new_loser_id INTEGER;
  v_player1_id INTEGER;
  v_player2_id INTEGER;
BEGIN
  -- Obtener información del partido actual
  SELECT player1_id, player2_id, winner_id
  INTO v_player1_id, v_player2_id, v_old_winner_id
  FROM matches
  WHERE id = p_match_id;

  -- Si el ganador no cambió, solo actualizar scores
  IF v_old_winner_id = p_new_winner_id THEN
    UPDATE matches
    SET player1_score = p_player1_score, player2_score = p_player2_score
    WHERE id = p_match_id;
    RETURN;
  END IF;

  -- Determinar perdedores
  IF v_old_winner_id = v_player1_id THEN
    v_old_loser_id := v_player2_id;
  ELSE
    v_old_loser_id := v_player1_id;
  END IF;

  IF p_new_winner_id = v_player1_id THEN
    v_new_loser_id := v_player2_id;
  ELSE
    v_new_loser_id := v_player1_id;
  END IF;

  -- Revertir estadísticas del ganador anterior
  UPDATE players
  SET 
    matches_won = GREATEST(0, matches_won - 1),
    points = GREATEST(0, matches_won - 1)
  WHERE id = v_old_winner_id;

  -- Actualizar estadísticas del nuevo ganador
  UPDATE players
  SET 
    matches_won = matches_won + 1,
    points = matches_won + 1
  WHERE id = p_new_winner_id;

  -- Recalcular rachas para ambos jugadores basándose en su historial
  -- Para el jugador 1
  PERFORM recalculate_streak(v_player1_id);
  
  -- Para el jugador 2
  PERFORM recalculate_streak(v_player2_id);

  -- Actualizar el partido
  UPDATE matches
  SET 
    winner_id = p_new_winner_id,
    player1_score = p_player1_score,
    player2_score = p_player2_score
  WHERE id = p_match_id;
END;
$$ LANGUAGE plpgsql;

-- 8. Crear función para recalcular racha de un jugador
CREATE OR REPLACE FUNCTION recalculate_streak(p_player_id INTEGER) RETURNS VOID AS $$
DECLARE
  v_current_streak INTEGER := 0;
  v_max_streak INTEGER := 0;
  v_temp_streak INTEGER := 0;
  match_record RECORD;
BEGIN
  -- Recorrer todos los partidos del jugador en orden cronológico
  FOR match_record IN
    SELECT winner_id, created_at
    FROM matches
    WHERE player1_id = p_player_id OR player2_id = p_player_id
    ORDER BY created_at ASC
  LOOP
    IF match_record.winner_id = p_player_id THEN
      -- Victoria: incrementar racha
      v_temp_streak := v_temp_streak + 1;
      v_max_streak := GREATEST(v_max_streak, v_temp_streak);
    ELSE
      -- Derrota: resetear racha temporal
      v_temp_streak := 0;
    END IF;
  END LOOP;

  -- La racha actual es la racha temporal al final
  v_current_streak := v_temp_streak;

  -- Actualizar el jugador
  UPDATE players
  SET 
    current_streak = v_current_streak,
    max_streak = v_max_streak
  WHERE id = p_player_id;
END;
$$ LANGUAGE plpgsql;

-- 9. Crear función simple para eliminar partido
CREATE OR REPLACE FUNCTION delete_match_simple(p_match_id INTEGER) RETURNS VOID AS $$
DECLARE
  v_winner_id INTEGER;
  v_player1_id INTEGER;
  v_player2_id INTEGER;
BEGIN
  -- Obtener información del partido
  SELECT player1_id, player2_id, winner_id
  INTO v_player1_id, v_player2_id, v_winner_id
  FROM matches
  WHERE id = p_match_id;

  -- Revertir estadísticas del ganador
  UPDATE players
  SET 
    matches_played = GREATEST(0, matches_played - 1),
    matches_won = GREATEST(0, matches_won - 1),
    points = GREATEST(0, matches_won - 1)
  WHERE id = v_winner_id;

  -- Revertir estadísticas del perdedor
  UPDATE players
  SET 
    matches_played = GREATEST(0, matches_played - 1)
  WHERE id = (CASE WHEN v_winner_id = v_player1_id THEN v_player2_id ELSE v_player1_id END);

  -- Eliminar el partido
  DELETE FROM matches WHERE id = p_match_id;

  -- Recalcular rachas para ambos jugadores
  PERFORM recalculate_streak(v_player1_id);
  PERFORM recalculate_streak(v_player2_id);
END;
$$ LANGUAGE plpgsql;
