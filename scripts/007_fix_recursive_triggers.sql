-- Fix the recursive trigger issue that causes stack depth exceeded error

-- Drop existing problematic triggers
DROP TRIGGER IF EXISTS handle_match_update_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_delete_trigger ON matches;

-- Drop the problematic functions
DROP FUNCTION IF EXISTS handle_match_update();
DROP FUNCTION IF EXISTS handle_match_delete();
DROP FUNCTION IF EXISTS recalculate_all_elo();

-- Create a simpler, non-recursive approach for match updates and deletions
-- This function will be called manually when needed, avoiding recursive triggers

CREATE OR REPLACE FUNCTION recalculate_all_elo_safe()
RETURNS VOID AS $$
DECLARE
    match_record RECORD;
    winner_elo INTEGER;
    loser_elo INTEGER;
    winner_streak INTEGER;
    loser_id INTEGER;
    calculated_elo_change INTEGER;
BEGIN
    -- Reset all players to starting values with explicit WHERE clause
    UPDATE players SET 
        elo_rating = 1200,
        current_streak = 0,
        max_streak = 0,
        matches_played = 0,
        matches_won = 0
    WHERE id IS NOT NULL; -- Explicit WHERE clause to satisfy database requirements
    
    -- Recalculate based on match history in chronological order
    FOR match_record IN 
        SELECT * FROM matches ORDER BY created_at ASC
    LOOP
        -- Get current stats before processing this match
        SELECT elo_rating, current_streak INTO winner_elo, winner_streak
        FROM players WHERE id = match_record.winner_id;
        
        -- Determine loser
        IF match_record.winner_id = match_record.player1_id THEN
            loser_id := match_record.player2_id;
        ELSE
            loser_id := match_record.player1_id;
        END IF;
        
        SELECT elo_rating INTO loser_elo FROM players WHERE id = loser_id;
        
        -- Calculate ELO change
        calculated_elo_change := calculate_elo_change(winner_elo, loser_elo, winner_streak);
        
        -- Update winner
        UPDATE players SET 
            elo_rating = elo_rating + calculated_elo_change,
            current_streak = current_streak + 1,
            max_streak = GREATEST(max_streak, current_streak + 1),
            matches_played = matches_played + 1,
            matches_won = matches_won + 1
        WHERE id = match_record.winner_id;
        
        -- Update loser
        UPDATE players SET 
            elo_rating = GREATEST(800, elo_rating - calculated_elo_change),
            current_streak = 0,
            matches_played = matches_played + 1
        WHERE id = loser_id;
        
        -- Update match with calculated ELO change
        UPDATE matches SET elo_change = calculated_elo_change WHERE id = match_record.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create new, simpler triggers that don't cause recursion
-- For match updates: recalculate all ELO after any match change
CREATE OR REPLACE FUNCTION handle_match_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Call the safe recalculation function
    PERFORM recalculate_all_elo_safe();
    
    -- Return appropriate record based on operation
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for both UPDATE and DELETE operations
CREATE TRIGGER handle_match_update_safe_trigger
    AFTER UPDATE ON matches
    FOR EACH ROW
    EXECUTE FUNCTION handle_match_change();

CREATE TRIGGER handle_match_delete_safe_trigger
    AFTER DELETE ON matches
    FOR EACH ROW
    EXECUTE FUNCTION handle_match_change();
