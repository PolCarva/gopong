-- Reset database and implement ELO system from scratch
-- This will delete all existing data and start fresh with ELO

-- Drop existing triggers and functions
DROP TRIGGER IF EXISTS update_player_points_trigger ON matches;
DROP FUNCTION IF EXISTS update_player_points();
DROP FUNCTION IF EXISTS calculate_elo_change(INTEGER, INTEGER, BOOLEAN);
DROP FUNCTION IF EXISTS update_elo_ratings();
DROP FUNCTION IF EXISTS recalculate_all_elo();

-- Clear all existing data
DELETE FROM matches;
DELETE FROM players;

-- Drop and recreate players table with ELO structure
DROP TABLE IF EXISTS players CASCADE;
CREATE TABLE players (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    elo_rating INTEGER DEFAULT 1200,
    current_streak INTEGER DEFAULT 0,
    max_streak INTEGER DEFAULT 0,
    matches_played INTEGER DEFAULT 0,
    matches_won INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Recreate matches table
DROP TABLE IF EXISTS matches CASCADE;
CREATE TABLE matches (
    id SERIAL PRIMARY KEY,
    player1_id INTEGER REFERENCES players(id) ON DELETE CASCADE,
    player2_id INTEGER REFERENCES players(id) ON DELETE CASCADE,
    winner_id INTEGER REFERENCES players(id) ON DELETE CASCADE,
    player1_score INTEGER NOT NULL,
    player2_score INTEGER NOT NULL,
    elo_change INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ELO calculation function
CREATE OR REPLACE FUNCTION calculate_elo_change(winner_elo INTEGER, loser_elo INTEGER, winner_streak INTEGER)
RETURNS INTEGER AS $$
DECLARE
    k_factor INTEGER := 32;
    expected_score NUMERIC;
    streak_multiplier NUMERIC := 1.0;
    elo_change INTEGER;
BEGIN
    -- Calculate expected score for winner
    expected_score := 1.0 / (1.0 + POWER(10.0, (loser_elo - winner_elo) / 400.0));
    
    -- Apply streak multiplier (slight bonus for streaks 3+)
    IF winner_streak >= 3 THEN
        streak_multiplier := 1.0 + LEAST(winner_streak - 2, 4) * 0.05; -- Max 20% bonus at 6 streak
    END IF;
    
    -- Calculate ELO change
    elo_change := ROUND(k_factor * (1.0 - expected_score) * streak_multiplier);
    
    RETURN elo_change;
END;
$$ LANGUAGE plpgsql;

-- Function to update ELO ratings and streaks
CREATE OR REPLACE FUNCTION update_elo_ratings()
RETURNS TRIGGER AS $$
DECLARE
    winner_elo INTEGER;
    loser_elo INTEGER;
    winner_streak INTEGER;
    loser_id INTEGER;
    elo_change INTEGER;
BEGIN
    -- Get current ELO ratings and winner's streak
    SELECT elo_rating, current_streak INTO winner_elo, winner_streak
    FROM players WHERE id = NEW.winner_id;
    
    -- Determine loser
    IF NEW.winner_id = NEW.player1_id THEN
        loser_id := NEW.player2_id;
    ELSE
        loser_id := NEW.player1_id;
    END IF;
    
    SELECT elo_rating INTO loser_elo FROM players WHERE id = loser_id;
    
    -- Calculate ELO change
    elo_change := calculate_elo_change(winner_elo, loser_elo, winner_streak);
    
    -- Update winner
    UPDATE players SET 
        elo_rating = elo_rating + elo_change,
        current_streak = current_streak + 1,
        max_streak = GREATEST(max_streak, current_streak + 1),
        matches_played = matches_played + 1,
        matches_won = matches_won + 1
    WHERE id = NEW.winner_id;
    
    -- Update loser
    UPDATE players SET 
        elo_rating = GREATEST(800, elo_rating - elo_change), -- Minimum ELO of 800
        current_streak = 0, -- Reset streak on loss
        matches_played = matches_played + 1
    WHERE id = loser_id;
    
    -- Store ELO change in match record
    NEW.elo_change := elo_change;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to recalculate all ELO ratings from scratch
CREATE OR REPLACE FUNCTION recalculate_all_elo()
RETURNS VOID AS $$
DECLARE
    match_record RECORD;
BEGIN
    -- Reset all players to starting values
    UPDATE players SET 
        elo_rating = 1200,
        current_streak = 0,
        max_streak = 0,
        matches_played = 0,
        matches_won = 0;
    
    -- Recalculate based on match history in chronological order
    FOR match_record IN 
        SELECT * FROM matches ORDER BY created_at ASC
    LOOP
        -- Temporarily update the match to trigger ELO recalculation
        UPDATE matches SET elo_change = 0 WHERE id = match_record.id;
        
        -- This will trigger the update_elo_ratings function
        UPDATE matches SET 
            winner_id = match_record.winner_id,
            elo_change = (
                SELECT calculate_elo_change(
                    (SELECT elo_rating FROM players WHERE id = match_record.winner_id),
                    (SELECT elo_rating FROM players WHERE id = 
                        CASE WHEN match_record.winner_id = match_record.player1_id 
                             THEN match_record.player2_id 
                             ELSE match_record.player1_id END),
                    (SELECT current_streak FROM players WHERE id = match_record.winner_id)
                )
            )
        WHERE id = match_record.id;
        
        -- Manual update since trigger might not fire on same value
        PERFORM update_elo_ratings_manual(match_record.id);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Helper function for manual ELO updates
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
    
    SELECT elo_rating, current_streak INTO winner_elo, winner_streak
    FROM players WHERE id = match_record.winner_id;
    
    IF match_record.winner_id = match_record.player1_id THEN
        loser_id := match_record.player2_id;
    ELSE
        loser_id := match_record.player1_id;
    END IF;
    
    SELECT elo_rating INTO loser_elo FROM players WHERE id = loser_id;
    
    elo_change := calculate_elo_change(winner_elo, loser_elo, winner_streak);
    
    UPDATE players SET 
        elo_rating = elo_rating + elo_change,
        current_streak = current_streak + 1,
        max_streak = GREATEST(max_streak, current_streak + 1),
        matches_played = matches_played + 1,
        matches_won = matches_won + 1
    WHERE id = match_record.winner_id;
    
    UPDATE players SET 
        elo_rating = GREATEST(800, elo_rating - elo_change),
        current_streak = 0,
        matches_played = matches_played + 1
    WHERE id = loser_id;
    
    UPDATE matches SET elo_change = elo_change WHERE id = match_id;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
CREATE TRIGGER update_elo_ratings_trigger
    BEFORE INSERT ON matches
    FOR EACH ROW
    EXECUTE FUNCTION update_elo_ratings();

-- Trigger for updates (when editing matches)
CREATE OR REPLACE FUNCTION handle_match_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Recalculate all ELO ratings when a match is updated
    PERFORM recalculate_all_elo();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER handle_match_update_trigger
    AFTER UPDATE ON matches
    FOR EACH ROW
    EXECUTE FUNCTION handle_match_update();

-- Trigger for deletions
CREATE OR REPLACE FUNCTION handle_match_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- Recalculate all ELO ratings when a match is deleted
    PERFORM recalculate_all_elo();
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER handle_match_delete_trigger
    AFTER DELETE ON matches
    FOR EACH ROW
    EXECUTE FUNCTION handle_match_delete();
