-- Create the missing recalculate_all_elo_safe function
-- This function recalculates all ELO ratings from scratch without triggering recursion

CREATE OR REPLACE FUNCTION recalculate_all_elo_safe()
RETURNS void AS $$
DECLARE
    match_record RECORD;
    player1_elo INTEGER;
    player2_elo INTEGER;
    expected_score_1 NUMERIC;
    expected_score_2 NUMERIC;
    actual_score_1 NUMERIC;
    actual_score_2 NUMERIC;
    new_elo_1 INTEGER;
    new_elo_2 INTEGER;
    elo_change_amount INTEGER;
    k_factor INTEGER := 32;
BEGIN
    -- Reset all players to starting values
    UPDATE players SET 
        elo_rating = 1200,
        current_streak = 0,
        max_streak = 0,
        matches_played = 0,
        matches_won = 0
    WHERE id > 0; -- Use WHERE clause to avoid "UPDATE requires WHERE clause" error
    
    -- Process all matches in chronological order
    FOR match_record IN 
        SELECT * FROM matches 
        ORDER BY created_at ASC
    LOOP
        -- Get current ELO ratings for both players
        SELECT elo_rating INTO player1_elo FROM players WHERE id = match_record.player1_id;
        SELECT elo_rating INTO player2_elo FROM players WHERE id = match_record.player2_id;
        
        -- Calculate expected scores
        expected_score_1 := 1.0 / (1.0 + POWER(10.0, (player2_elo - player1_elo) / 400.0));
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
        new_elo_1 := player1_elo + ROUND(k_factor * (actual_score_1 - expected_score_1));
        new_elo_2 := player2_elo + ROUND(k_factor * (actual_score_2 - expected_score_2));
        
        -- Calculate ELO change for the match record
        elo_change_amount := ABS(new_elo_1 - player1_elo);
        
        -- Update player 1
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
        
        -- Update player 2
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
        
        -- Update the match record with the ELO change (without triggering recursion)
        UPDATE matches SET elo_change = elo_change_amount WHERE id = match_record.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
