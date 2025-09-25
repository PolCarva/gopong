-- Remove all problematic triggers and functions that cause recursion
-- This script completely removes the recursive triggers and replaces them with a simpler approach

-- Drop all existing triggers first
DROP TRIGGER IF EXISTS handle_match_insert_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_update_trigger ON matches;
DROP TRIGGER IF EXISTS handle_match_delete_trigger ON matches;

-- Drop all problematic functions
DROP FUNCTION IF EXISTS handle_match_insert();
DROP FUNCTION IF EXISTS handle_match_update();
DROP FUNCTION IF EXISTS handle_match_delete();
DROP FUNCTION IF EXISTS recalculate_all_elo();
DROP FUNCTION IF EXISTS recalculate_all_elo_safe();
DROP FUNCTION IF EXISTS update_elo_ratings_manual(INTEGER);

-- Create a simple, non-recursive function to update ELO ratings for a specific match
CREATE OR REPLACE FUNCTION update_match_elo(match_id INTEGER)
RETURNS void AS $$
DECLARE
    match_record RECORD;
    player1_current_elo INTEGER;
    player2_current_elo INTEGER;
    expected_score_1 NUMERIC;
    expected_score_2 NUMERIC;
    actual_score_1 NUMERIC;
    actual_score_2 NUMERIC;
    new_elo_1 INTEGER;
    new_elo_2 INTEGER;
    elo_change_amount INTEGER;
    k_factor INTEGER := 32;
BEGIN
    -- Get match details
    SELECT * INTO match_record FROM matches WHERE id = match_id;
    
    IF NOT FOUND THEN
        RETURN;
    END IF;
    
    -- Get current ELO ratings
    SELECT elo_rating INTO player1_current_elo FROM players WHERE id = match_record.player1_id;
    SELECT elo_rating INTO player2_current_elo FROM players WHERE id = match_record.player2_id;
    
    -- Calculate expected scores
    expected_score_1 := 1.0 / (1.0 + POWER(10.0, (player2_current_elo - player1_current_elo) / 400.0));
    expected_score_2 := 1.0 - expected_score_1;
    
    -- Determine actual scores based on winner
    IF match_record.winner_id = match_record.player1_id THEN
        actual_score_1 := 1.0;
        actual_score_2 := 0.0;
    ELSE
        actual_score_1 := 0.0;
        actual_score_2 := 1.0;
    END IF;
    
    -- Calculate new ELO ratings
    new_elo_1 := player1_current_elo + ROUND(k_factor * (actual_score_1 - expected_score_1));
    new_elo_2 := player2_current_elo + ROUND(k_factor * (actual_score_2 - expected_score_2));
    
    -- Calculate ELO change for the match record
    elo_change_amount := ABS(new_elo_1 - player1_current_elo);
    
    -- Update players' ELO ratings and stats
    UPDATE players SET 
        elo_rating = new_elo_1,
        matches_played = matches_played + 1,
        matches_won = CASE WHEN match_record.winner_id = id THEN matches_won + 1 ELSE matches_won END,
        current_streak = CASE 
            WHEN match_record.winner_id = id THEN current_streak + 1 
            ELSE 0 
        END,
        max_streak = CASE 
            WHEN match_record.winner_id = id AND current_streak + 1 > max_streak THEN current_streak + 1
            ELSE max_streak 
        END
    WHERE id = match_record.player1_id;
    
    UPDATE players SET 
        elo_rating = new_elo_2,
        matches_played = matches_played + 1,
        matches_won = CASE WHEN match_record.winner_id = id THEN matches_won + 1 ELSE matches_won END,
        current_streak = CASE 
            WHEN match_record.winner_id = id THEN current_streak + 1 
            ELSE 0 
        END,
        max_streak = CASE 
            WHEN match_record.winner_id = id AND current_streak + 1 > max_streak THEN current_streak + 1
            ELSE max_streak 
        END
    WHERE id = match_record.player2_id;
    
    -- Update the match record with the ELO change
    UPDATE matches SET elo_change = elo_change_amount WHERE id = match_id;
END;
$$ LANGUAGE plpgsql;

-- Create simple, non-recursive triggers that only update the specific match
CREATE OR REPLACE FUNCTION handle_match_insert_simple()
RETURNS TRIGGER AS $$
BEGIN
    -- Update ELO for this specific match only
    PERFORM update_match_elo(NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for new matches only
CREATE TRIGGER handle_match_insert_simple_trigger
    AFTER INSERT ON matches
    FOR EACH ROW
    EXECUTE FUNCTION handle_match_insert_simple();

-- For updates and deletes, we'll handle them manually in the application code
-- to avoid any recursion issues
