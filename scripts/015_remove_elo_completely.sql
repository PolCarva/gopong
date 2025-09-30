-- Eliminar COMPLETAMENTE el sistema ELO y usar sistema simple de puntos
-- +1 punto por victoria, -1 punto por derrota

-- 1. Eliminar todas las funciones relacionadas con ELO
DROP FUNCTION IF EXISTS add_match_with_both_scenarios CASCADE;
DROP FUNCTION IF EXISTS edit_match_with_scenarios CASCADE;
DROP FUNCTION IF EXISTS delete_match_with_scenarios CASCADE;
DROP FUNCTION IF EXISTS add_match_with_elo_changes CASCADE;
DROP FUNCTION IF EXISTS edit_match_with_elo_changes CASCADE;
DROP FUNCTION IF EXISTS delete_match_with_elo_revert CASCADE;
DROP FUNCTION IF EXISTS add_match_simple CASCADE;
DROP FUNCTION IF EXISTS edit_match_simple CASCADE;
DROP FUNCTION IF EXISTS delete_match_simple CASCADE;
DROP FUNCTION IF EXISTS update_player_elo_simple CASCADE;
DROP FUNCTION IF EXISTS revert_player_elo_simple CASCADE;
DROP FUNCTION IF EXISTS calculate_elo_change CASCADE;
DROP FUNCTION IF EXISTS recalculate_all_elo CASCADE;
DROP FUNCTION IF EXISTS recalculate_all_elo_safe CASCADE;
DROP FUNCTION IF EXISTS handle_match_change CASCADE;

-- 2. Eliminar todos los triggers
DROP TRIGGER IF EXISTS handle_match_update_safe_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_delete_safe_trigger ON matches;
DROP TRIGGER IF EXISTS update_elo_on_match_insert ON matches;
DROP TRIGGER IF EXISTS update_elo_on_match_update ON matches;
DROP TRIGGER IF EXISTS update_elo_on_match_delete ON matches;

-- 3. Limpiar todos los datos existentes
DELETE FROM matches;
DELETE FROM players;

-- 4. Modificar la tabla players - eliminar ELO, agregar points
ALTER TABLE players DROP COLUMN IF EXISTS elo_rating CASCADE;
ALTER TABLE players ADD COLUMN IF NOT EXISTS points INTEGER DEFAULT 0;

-- 5. Modificar la tabla matches - eliminar columnas ELO existentes según el esquema actual
ALTER TABLE matches DROP COLUMN IF EXISTS elo_change CASCADE;
ALTER TABLE matches DROP COLUMN IF EXISTS player1_elo_change CASCADE;
ALTER TABLE matches DROP COLUMN IF EXISTS player2_elo_change CASCADE;
ALTER TABLE matches DROP COLUMN IF EXISTS player1_win_elo_change CASCADE;
ALTER TABLE matches DROP COLUMN IF EXISTS player1_lose_elo_change CASCADE;
ALTER TABLE matches DROP COLUMN IF EXISTS player2_win_elo_change CASCADE;
ALTER TABLE matches DROP COLUMN IF EXISTS player2_lose_elo_change CASCADE;
ALTER TABLE matches DROP COLUMN IF EXISTS player1_score CASCADE;
ALTER TABLE matches DROP COLUMN IF EXISTS player2_score CASCADE;

-- 6. Crear función simple para agregar partido
CREATE OR REPLACE FUNCTION add_match_simple(
  p_player1_id INTEGER,
  p_player2_id INTEGER,
  p_winner_id INTEGER
)
RETURNS void AS $$
DECLARE
  v_loser_id INTEGER;
BEGIN
  -- Insertar el partido
  INSERT INTO matches (player1_id, player2_id, winner_id)
  VALUES (p_player1_id, p_player2_id, p_winner_id);
  
  -- Determinar el perdedor
  IF p_winner_id = p_player1_id THEN
    v_loser_id := p_player2_id;
  ELSE
    v_loser_id := p_player1_id;
  END IF;
  
  -- Actualizar puntos: +1 para ganador, -1 para perdedor
  UPDATE players 
  SET 
    points = points + 1,
    matches_played = matches_played + 1,
    matches_won = matches_won + 1,
    current_streak = current_streak + 1,
    max_streak = GREATEST(max_streak, current_streak + 1)
  WHERE id = p_winner_id;
  
  UPDATE players 
  SET 
    points = points - 1,
    matches_played = matches_played + 1,
    current_streak = 0
  WHERE id = v_loser_id;
END;
$$ LANGUAGE plpgsql;

-- 7. Crear función simple para editar partido
CREATE OR REPLACE FUNCTION edit_match_simple(
  p_match_id INTEGER,
  p_new_winner_id INTEGER
)
RETURNS void AS $$
DECLARE
  v_old_winner_id INTEGER;
  v_player1_id INTEGER;
  v_player2_id INTEGER;
  v_old_loser_id INTEGER;
  v_new_loser_id INTEGER;
BEGIN
  -- Obtener información del partido actual
  SELECT winner_id, player1_id, player2_id
  INTO v_old_winner_id, v_player1_id, v_player2_id
  FROM matches
  WHERE id = p_match_id;
  
  -- Si el ganador no cambió, no hacer nada
  IF v_old_winner_id = p_new_winner_id THEN
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
  
  -- Revertir cambios del ganador anterior: -1 punto, -1 victoria
  UPDATE players 
  SET 
    points = points - 1,
    matches_won = matches_won - 1
  WHERE id = v_old_winner_id;
  
  -- Revertir cambios del perdedor anterior: +1 punto
  UPDATE players 
  SET 
    points = points + 1
  WHERE id = v_old_loser_id;
  
  -- Aplicar cambios al nuevo ganador: +1 punto, +1 victoria
  UPDATE players 
  SET 
    points = points + 1,
    matches_won = matches_won + 1
  WHERE id = p_new_winner_id;
  
  -- Aplicar cambios al nuevo perdedor: -1 punto
  UPDATE players 
  SET 
    points = points - 1
  WHERE id = v_new_loser_id;
  
  -- Actualizar el partido
  UPDATE matches
  SET winner_id = p_new_winner_id
  WHERE id = p_match_id;
  
  -- Recalcular rachas para ambos jugadores
  PERFORM recalculate_streaks(v_old_winner_id);
  PERFORM recalculate_streaks(v_old_loser_id);
  PERFORM recalculate_streaks(p_new_winner_id);
  PERFORM recalculate_streaks(v_new_loser_id);
END;
$$ LANGUAGE plpgsql;

-- 8. Crear función simple para eliminar partido
CREATE OR REPLACE FUNCTION delete_match_simple(
  p_match_id INTEGER
)
RETURNS void AS $$
DECLARE
  v_winner_id INTEGER;
  v_player1_id INTEGER;
  v_player2_id INTEGER;
  v_loser_id INTEGER;
BEGIN
  -- Obtener información del partido
  SELECT winner_id, player1_id, player2_id
  INTO v_winner_id, v_player1_id, v_player2_id
  FROM matches
  WHERE id = p_match_id;
  
  -- Determinar el perdedor
  IF v_winner_id = v_player1_id THEN
    v_loser_id := v_player2_id;
  ELSE
    v_loser_id := v_player1_id;
  END IF;
  
  -- Revertir cambios del ganador: -1 punto, -1 victoria, -1 partido jugado
  UPDATE players 
  SET 
    points = points - 1,
    matches_played = matches_played - 1,
    matches_won = matches_won - 1
  WHERE id = v_winner_id;
  
  -- Revertir cambios del perdedor: +1 punto, -1 partido jugado
  UPDATE players 
  SET 
    points = points + 1,
    matches_played = matches_played - 1
  WHERE id = v_loser_id;
  
  -- Eliminar el partido
  DELETE FROM matches WHERE id = p_match_id;
  
  -- Recalcular rachas para ambos jugadores
  PERFORM recalculate_streaks(v_winner_id);
  PERFORM recalculate_streaks(v_loser_id);
END;
$$ LANGUAGE plpgsql;

-- 9. Crear función para recalcular rachas
CREATE OR REPLACE FUNCTION recalculate_streaks(p_player_id INTEGER)
RETURNS void AS $$
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
