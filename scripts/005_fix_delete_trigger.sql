-- Fix the delete trigger issue by correcting the UPDATE without WHERE clause

-- Drop the problematic function and recreate it with proper WHERE clauses
DROP FUNCTION IF EXISTS recalculate_all_elo();

-- Function to recalculate all ELO ratings from scratch
CREATE OR REPLACE FUNCTION recalculate_all_elo()
RETURNS VOID AS $$
DECLARE
    match_record RECORD;
    player_record RECORD;
BEGIN
    -- Reset all players to starting values (with WHERE clause for safety)
    FOR player_record IN SELECT id FROM players LOOP
        UPDATE players SET 
            elo_rating = 1200,
            current_streak = 0,
            max_streak = 0,
            matches_played = 0,
            matches_won = 0
        WHERE id = player_record.id;
    END LOOP;
    
    -- Recalculate based on match history in chronological order
    FOR match_record IN 
        SELECT * FROM matches ORDER BY created_at ASC
    LOOP
        -- Manual update for each match
        PERFORM update_elo_ratings_manual(match_record.id);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Also fix the helper function to ensure it has proper WHERE clauses
DROP FUNCTION IF EXISTS update_elo_ratings_manual(INTEGER);

CREATE OR REPLACE FUNCTION update_elo_ratings_manual(match_id INTEGER)
RETURNS VOID AS $$
DECLARE
    match_record RECORD;
    winner_elo INTEGER;
    loser_elo INTEGER;
    winner_streak INTEGER;
    loser_id INTEGER;
    elo_change INTEGER;
BEGIN
    SELECT * INTO match_record FROM matches WHERE id = match_id;
    
    -- Get current stats before the match
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
    elo_change := calculate_elo_change(winner_elo, loser_elo, winner_streak);
    
    -- Update winner with explicit WHERE clause
    UPDATE players SET 
        elo_rating = elo_rating + elo_change,
        current_streak = current_streak + 1,
        max_streak = GREATEST(max_streak, current_streak + 1),
        matches_played = matches_played + 1,
        matches_won = matches_won + 1
    WHERE id = match_record.winner_id;
    
    -- Update loser with explicit WHERE clause
    UPDATE players SET 
        elo_rating = GREATEST(800, elo_rating - elo_change),
        current_streak = 0,
        matches_played = matches_played + 1
    WHERE id = loser_id;
    
    -- Update match record with explicit WHERE clause
    UPDATE matches SET elo_change = elo_change WHERE id = match_id;
END;
$$ LANGUAGE plpgsql;
