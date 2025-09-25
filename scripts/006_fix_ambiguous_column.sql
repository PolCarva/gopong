-- Fix the ambiguous column reference in the update_elo_ratings_manual function

DROP FUNCTION IF EXISTS update_elo_ratings_manual(INTEGER);

CREATE OR REPLACE FUNCTION update_elo_ratings_manual(match_id INTEGER)
RETURNS VOID AS $$
DECLARE
    match_record RECORD;
    winner_elo INTEGER;
    loser_elo INTEGER;
    winner_streak INTEGER;
    loser_id INTEGER;
    calculated_elo_change INTEGER; -- Renamed variable to avoid ambiguity
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
    calculated_elo_change := calculate_elo_change(winner_elo, loser_elo, winner_streak);
    
    -- Update winner with explicit WHERE clause
    UPDATE players SET 
        elo_rating = elo_rating + calculated_elo_change,
        current_streak = current_streak + 1,
        max_streak = GREATEST(max_streak, current_streak + 1),
        matches_played = matches_played + 1,
        matches_won = matches_won + 1
    WHERE id = match_record.winner_id;
    
    -- Update loser with explicit WHERE clause
    UPDATE players SET 
        elo_rating = GREATEST(800, elo_rating - calculated_elo_change),
        current_streak = 0,
        matches_played = matches_played + 1
    WHERE id = loser_id;
    
    -- Fixed ambiguous column reference by using the renamed variable
    UPDATE matches SET elo_change = calculated_elo_change WHERE id = match_id;
END;
$$ LANGUAGE plpgsql;
