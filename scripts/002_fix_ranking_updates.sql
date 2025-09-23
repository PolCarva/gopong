-- Eliminar el trigger y función existentes para recrearlos con mejor lógica
DROP TRIGGER IF EXISTS update_points_on_match_insert ON matches;
DROP FUNCTION IF EXISTS update_player_points();

-- Crear función mejorada para manejar INSERT de partidos
CREATE OR REPLACE FUNCTION handle_match_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- Incrementar puntos del ganador
  UPDATE players 
  SET points = points + 1 
  WHERE id = NEW.winner_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear función para manejar UPDATE de partidos
CREATE OR REPLACE FUNCTION handle_match_update()
RETURNS TRIGGER AS $$
BEGIN
  -- Si cambió el ganador, actualizar puntos
  IF OLD.winner_id != NEW.winner_id THEN
    -- Restar punto al ganador anterior
    UPDATE players 
    SET points = points - 1 
    WHERE id = OLD.winner_id;
    
    -- Sumar punto al nuevo ganador
    UPDATE players 
    SET points = points + 1 
    WHERE id = NEW.winner_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear función para manejar DELETE de partidos
CREATE OR REPLACE FUNCTION handle_match_delete()
RETURNS TRIGGER AS $$
BEGIN
  -- Restar punto al ganador del partido eliminado
  UPDATE players 
  SET points = points - 1 
  WHERE id = OLD.winner_id;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Crear triggers para INSERT, UPDATE y DELETE
CREATE TRIGGER handle_match_insert_trigger
  AFTER INSERT ON matches
  FOR EACH ROW
  EXECUTE FUNCTION handle_match_insert();

CREATE TRIGGER handle_match_update_trigger
  AFTER UPDATE ON matches
  FOR EACH ROW
  EXECUTE FUNCTION handle_match_update();

CREATE TRIGGER handle_match_delete_trigger
  AFTER DELETE ON matches
  FOR EACH ROW
  EXECUTE FUNCTION handle_match_delete();

-- Función para recalcular todos los puntos (útil para verificar consistencia)
CREATE OR REPLACE FUNCTION recalculate_all_points()
RETURNS void AS $$
BEGIN
  -- Resetear todos los puntos a 0
  UPDATE players SET points = 0;
  
  -- Recalcular puntos basado en partidos existentes
  UPDATE players 
  SET points = (
    SELECT COUNT(*) 
    FROM matches 
    WHERE matches.winner_id = players.id
  );
END;
$$ LANGUAGE plpgsql;
