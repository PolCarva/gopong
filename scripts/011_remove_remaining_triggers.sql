-- Remove all remaining triggers that reference the dropped functions
-- This fixes the "function recalculate_all_elo_safe() does not exist" error

-- Drop the triggers created in script 007 that are still active
DROP TRIGGER IF EXISTS handle_match_update_safe_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_delete_safe_trigger ON matches;

-- Drop the function that these triggers were calling
DROP FUNCTION IF EXISTS handle_match_change();

-- Ensure no other triggers are left that might cause issues
DROP TRIGGER IF EXISTS handle_match_insert_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_update_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_delete_trigger ON matches;

-- Drop any remaining functions that might cause recursion
DROP FUNCTION IF EXISTS handle_match_insert();
DROP FUNCTION IF EXISTS handle_match_update();
DROP FUNCTION IF EXISTS handle_match_delete();
DROP FUNCTION IF EXISTS recalculate_all_elo();
DROP FUNCTION IF EXISTS recalculate_all_elo_safe();
DROP FUNCTION IF EXISTS update_elo_ratings_manual(integer);

-- Verify that the simple ELO functions exist (recreate if needed)
CREATE OR REPLACE FUNCTION update_player_elo_simple(
    winner_id integer,
    loser_id integer,
    winner_score integer DEFAULT 1,
    loser_score integer DEFAULT 0
) RETURNS void AS $$
DECLARE
    winner_elo integer;
    loser_elo integer;
    expected_winner float;
    expected_loser float;
    new_winner_elo integer;
    new_loser_elo integer;
    k_factor integer := 32;
BEGIN
    -- Obtener ratings actuales
    SELECT elo_rating INTO winner_elo FROM players WHERE id = winner_id;
    SELECT elo_rating INTO loser_elo FROM players WHERE id = loser_id;
    
    -- Calcular probabilidades esperadas
    expected_winner := 1.0 / (1.0 + power(10.0, (loser_elo - winner_elo) / 400.0));
    expected_loser := 1.0 - expected_winner;
    
    -- Calcular nuevos ratings
    new_winner_elo := winner_elo + round(k_factor * (1 - expected_winner));
    new_loser_elo := loser_elo + round(k_factor * (0 - expected_loser));
    
    -- Actualizar ganador
    UPDATE players SET 
        elo_rating = new_winner_elo,
        matches_played = matches_played + 1,
        matches_won = matches_won + 1,
        current_streak = current_streak + 1,
        max_streak = GREATEST(max_streak, current_streak + 1)
    WHERE id = winner_id;
    
    -- Actualizar perdedor
    UPDATE players SET 
        elo_rating = new_loser_elo,
        matches_played = matches_played + 1,
        current_streak = 0
    WHERE id = loser_id;
END;
$$ LANGUAGE plpgsql;

-- Función simple para revertir ELO cuando se elimina un partido
CREATE OR REPLACE FUNCTION revert_player_elo_simple(
    winner_id integer,
    loser_id integer,
    winner_score integer DEFAULT 1,
    loser_score integer DEFAULT 0
) RETURNS void AS $$
DECLARE
    winner_elo integer;
    loser_elo integer;
    expected_winner float;
    expected_loser float;
    reverted_winner_elo integer;
    reverted_loser_elo integer;
    k_factor integer := 32;
BEGIN
    -- Obtener ratings actuales
    SELECT elo_rating INTO winner_elo FROM players WHERE id = winner_id;
    SELECT elo_rating INTO loser_elo FROM players WHERE id = loser_id;
    
    -- Calcular probabilidades esperadas (invertidas para revertir)
    expected_winner := 1.0 / (1.0 + power(10.0, (loser_elo - winner_elo) / 400.0));
    expected_loser := 1.0 - expected_winner;
    
    -- Revertir los cambios de ELO
    reverted_winner_elo := winner_elo - round(k_factor * (1 - expected_winner));
    reverted_loser_elo := loser_elo - round(k_factor * (0 - expected_loser));
    
    -- Actualizar ganador (revertir)
    UPDATE players SET 
        elo_rating = reverted_winner_elo,
        matches_played = GREATEST(0, matches_played - 1),
        matches_won = GREATEST(0, matches_won - 1)
    WHERE id = winner_id;
    
    -- Actualizar perdedor (revertir)
    UPDATE players SET 
        elo_rating = reverted_loser_elo,
        matches_played = GREATEST(0, matches_played - 1)
    WHERE id = loser_id;
END;
$$ LANGUAGE plpgsql;
