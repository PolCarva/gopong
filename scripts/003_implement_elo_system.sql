-- Migración para implementar sistema ELO con rachas

-- Agregar nuevas columnas a la tabla players
ALTER TABLE players 
ADD COLUMN IF NOT EXISTS elo_rating INTEGER DEFAULT 1200,
ADD COLUMN IF NOT EXISTS current_streak INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS max_streak INTEGER DEFAULT 0;

-- Eliminar triggers y funciones anteriores
DROP TRIGGER IF EXISTS update_points_on_match_insert ON matches;
DROP TRIGGER IF EXISTS update_points_on_match_update ON matches;
DROP TRIGGER IF EXISTS update_points_on_match_delete ON matches;
DROP FUNCTION IF EXISTS update_player_points();
DROP FUNCTION IF EXISTS handle_match_update();
DROP FUNCTION IF EXISTS handle_match_delete();

-- Función para calcular cambio de ELO
CREATE OR REPLACE FUNCTION calculate_elo_change(winner_elo INTEGER, loser_elo INTEGER, winner_streak INTEGER)
RETURNS INTEGER AS $$
DECLARE
  expected_score FLOAT;
  k_factor INTEGER := 32;
  streak_multiplier FLOAT := 1.0;
  elo_change INTEGER;
BEGIN
  -- Calcular probabilidad esperada de victoria
  expected_score := 1.0 / (1.0 + POWER(10.0, (loser_elo - winner_elo) / 400.0));
  
  -- Aplicar multiplicador de racha (leve ventaja después de 3 victorias)
  IF winner_streak >= 3 THEN
    streak_multiplier := 1.0 + (LEAST(winner_streak, 6) - 2) * 0.05; -- Máximo 20% extra con racha de 6
  END IF;
  
  -- Calcular cambio de ELO
  elo_change := ROUND(k_factor * (1.0 - expected_score) * streak_multiplier);
  
  -- Mínimo cambio de 1 punto para evitar estancamiento
  IF elo_change < 1 THEN
    elo_change := 1;
  END IF;
  
  RETURN elo_change;
END;
$$ LANGUAGE plpgsql;

-- Función para actualizar ELO y rachas cuando se agrega un partido
CREATE OR REPLACE FUNCTION update_elo_on_match_insert()
RETURNS TRIGGER AS $$
DECLARE
  winner_elo INTEGER;
  loser_elo INTEGER;
  winner_streak INTEGER;
  loser_id UUID;
  elo_change INTEGER;
BEGIN
  -- Determinar quién perdió
  IF NEW.winner_id = NEW.player1_id THEN
    loser_id := NEW.player2_id;
  ELSE
    loser_id := NEW.player1_id;
  END IF;
  
  -- Obtener ELO y racha actual del ganador y perdedor
  SELECT elo_rating, current_streak INTO winner_elo, winner_streak
  FROM players WHERE id = NEW.winner_id;
  
  SELECT elo_rating INTO loser_elo
  FROM players WHERE id = loser_id;
  
  -- Calcular cambio de ELO
  elo_change := calculate_elo_change(winner_elo, loser_elo, winner_streak);
  
  -- Actualizar ganador: sumar ELO, incrementar racha
  UPDATE players 
  SET 
    elo_rating = elo_rating + elo_change,
    current_streak = current_streak + 1,
    max_streak = GREATEST(max_streak, current_streak + 1)
  WHERE id = NEW.winner_id;
  
  -- Actualizar perdedor: restar ELO (la mitad del cambio), resetear racha
  UPDATE players 
  SET 
    elo_rating = GREATEST(800, elo_rating - (elo_change / 2)), -- Mínimo ELO de 800
    current_streak = 0
  WHERE id = loser_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Función para manejar actualizaciones de partidos
CREATE OR REPLACE FUNCTION handle_elo_match_update()
RETURNS TRIGGER AS $$
DECLARE
  old_winner_id UUID := OLD.winner_id;
  old_loser_id UUID;
  new_winner_id UUID := NEW.winner_id;
  new_loser_id UUID;
BEGIN
  -- Si no cambió el ganador, no hacer nada
  IF old_winner_id = new_winner_id THEN
    RETURN NEW;
  END IF;
  
  -- Determinar perdedores antiguos y nuevos
  IF old_winner_id = OLD.player1_id THEN
    old_loser_id := OLD.player2_id;
  ELSE
    old_loser_id := OLD.player1_id;
  END IF;
  
  IF new_winner_id = NEW.player1_id THEN
    new_loser_id := NEW.player2_id;
  ELSE
    new_loser_id := NEW.player1_id;
  END IF;
  
  -- Recalcular todos los ELO y rachas desde cero
  PERFORM recalculate_all_elo_ratings();
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Función para manejar eliminación de partidos
CREATE OR REPLACE FUNCTION handle_elo_match_delete()
RETURNS TRIGGER AS $$
BEGIN
  -- Recalcular todos los ELO y rachas desde cero
  PERFORM recalculate_all_elo_ratings();
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Función para recalcular todos los ELO y rachas desde cero
CREATE OR REPLACE FUNCTION recalculate_all_elo_ratings()
RETURNS VOID AS $$
DECLARE
  match_record RECORD;
  winner_elo INTEGER;
  loser_elo INTEGER;
  winner_streak INTEGER;
  loser_id UUID;
  elo_change INTEGER;
BEGIN
  -- Resetear todos los jugadores a valores iniciales
  UPDATE players 
  SET 
    elo_rating = 1200,
    current_streak = 0,
    max_streak = 0;
  
  -- Procesar todos los partidos en orden cronológico
  FOR match_record IN 
    SELECT * FROM matches ORDER BY created_at ASC
  LOOP
    -- Determinar quién perdió
    IF match_record.winner_id = match_record.player1_id THEN
      loser_id := match_record.player2_id;
    ELSE
      loser_id := match_record.player1_id;
    END IF;
    
    -- Obtener ELO y racha actual del ganador y perdedor
    SELECT elo_rating, current_streak INTO winner_elo, winner_streak
    FROM players WHERE id = match_record.winner_id;
    
    SELECT elo_rating INTO loser_elo
    FROM players WHERE id = loser_id;
    
    -- Calcular cambio de ELO
    elo_change := calculate_elo_change(winner_elo, loser_elo, winner_streak);
    
    -- Actualizar ganador
    UPDATE players 
    SET 
      elo_rating = elo_rating + elo_change,
      current_streak = current_streak + 1,
      max_streak = GREATEST(max_streak, current_streak + 1)
    WHERE id = match_record.winner_id;
    
    -- Actualizar perdedor
    UPDATE players 
    SET 
      elo_rating = GREATEST(800, elo_rating - (elo_change / 2)),
      current_streak = 0
    WHERE id = loser_id;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Crear nuevos triggers
CREATE TRIGGER update_elo_on_match_insert
  AFTER INSERT ON matches
  FOR EACH ROW
  EXECUTE FUNCTION update_elo_on_match_insert();

CREATE TRIGGER update_elo_on_match_update
  AFTER UPDATE ON matches
  FOR EACH ROW
  EXECUTE FUNCTION handle_elo_match_update();

CREATE TRIGGER update_elo_on_match_delete
  AFTER DELETE ON matches
  FOR EACH ROW
  EXECUTE FUNCTION handle_elo_match_delete();

-- Recalcular ELO para datos existentes
SELECT recalculate_all_elo_ratings();
