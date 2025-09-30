-- Implementar sistema ELO con cambios almacenados
-- Esto permite editar/eliminar partidos simplemente sumando/restando los cambios guardados

-- Primero, agregar columnas para almacenar los cambios ELO de cada jugador
ALTER TABLE matches 
ADD COLUMN IF NOT EXISTS player1_elo_change INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS player2_elo_change INTEGER DEFAULT 0;

-- Función para calcular cambio ELO entre dos jugadores
CREATE OR REPLACE FUNCTION calculate_elo_change(
    rating1 INTEGER,
    rating2 INTEGER,
    player1_won BOOLEAN,
    k_factor INTEGER DEFAULT 32
) RETURNS INTEGER AS $$
DECLARE
    expected_score1 DECIMAL;
    actual_score1 INTEGER;
    elo_change INTEGER;
BEGIN
    -- Calcular probabilidad esperada para jugador 1
    expected_score1 := 1.0 / (1.0 + POWER(10.0, (rating2 - rating1) / 400.0));
    
    -- Puntaje real (1 si ganó, 0 si perdió)
    actual_score1 := CASE WHEN player1_won THEN 1 ELSE 0 END;
    
    -- Calcular cambio ELO
    elo_change := ROUND(k_factor * (actual_score1 - expected_score1));
    
    RETURN elo_change;
END;
$$ LANGUAGE plpgsql;

-- Función para agregar un partido con cambios ELO calculados y almacenados
CREATE OR REPLACE FUNCTION add_match_with_elo_changes(
    p_player1_id INTEGER,
    p_player2_id INTEGER,
    p_winner_id INTEGER,
    p_player1_score INTEGER,
    p_player2_score INTEGER
) RETURNS INTEGER AS $$
DECLARE
    player1_rating INTEGER;
    player2_rating INTEGER;
    player1_elo_change INTEGER;
    player2_elo_change INTEGER;
    match_id INTEGER;
BEGIN
    -- Obtener ratings actuales
    SELECT elo_rating INTO player1_rating FROM players WHERE id = p_player1_id;
    SELECT elo_rating INTO player2_rating FROM players WHERE id = p_player2_id;
    
    -- Calcular cambios ELO
    player1_elo_change := calculate_elo_change(
        player1_rating, 
        player2_rating, 
        p_winner_id = p_player1_id
    );
    player2_elo_change := -player1_elo_change; -- El cambio del jugador 2 es opuesto al del jugador 1
    
    -- Insertar el partido con los cambios calculados
    INSERT INTO matches (
        player1_id, player2_id, winner_id, 
        player1_score, player2_score,
        player1_elo_change, player2_elo_change,
        elo_change
    ) VALUES (
        p_player1_id, p_player2_id, p_winner_id,
        p_player1_score, p_player2_score,
        player1_elo_change, player2_elo_change,
        ABS(player1_elo_change) -- Mantener compatibilidad con campo existente
    ) RETURNING id INTO match_id;
    
    -- Aplicar cambios ELO a los jugadores
    UPDATE players 
    SET 
        elo_rating = elo_rating + player1_elo_change,
        matches_played = matches_played + 1,
        matches_won = CASE WHEN p_winner_id = p_player1_id THEN matches_won + 1 ELSE matches_won END,
        current_streak = CASE 
            WHEN p_winner_id = p_player1_id THEN current_streak + 1 
            ELSE 0 
        END,
        max_streak = CASE 
            WHEN p_winner_id = p_player1_id AND current_streak + 1 > max_streak 
            THEN current_streak + 1 
            ELSE max_streak 
        END
    WHERE id = p_player1_id;
    
    UPDATE players 
    SET 
        elo_rating = elo_rating + player2_elo_change,
        matches_played = matches_played + 1,
        matches_won = CASE WHEN p_winner_id = p_player2_id THEN matches_won + 1 ELSE matches_won END,
        current_streak = CASE 
            WHEN p_winner_id = p_player2_id THEN current_streak + 1 
            ELSE 0 
        END,
        max_streak = CASE 
            WHEN p_winner_id = p_player2_id AND current_streak + 1 > max_streak 
            THEN current_streak + 1 
            ELSE max_streak 
        END
    WHERE id = p_player2_id;
    
    RETURN match_id;
END;
$$ LANGUAGE plpgsql;

-- Función para editar un partido (revertir cambios anteriores y aplicar nuevos)
CREATE OR REPLACE FUNCTION edit_match_with_elo_changes(
    p_match_id INTEGER,
    p_new_winner_id INTEGER,
    p_new_player1_score INTEGER,
    p_new_player2_score INTEGER
) RETURNS VOID AS $$
DECLARE
    old_match RECORD;
    new_player1_elo_change INTEGER;
    new_player2_elo_change INTEGER;
    player1_rating INTEGER;
    player2_rating INTEGER;
BEGIN
    -- Obtener datos del partido actual
    SELECT * INTO old_match FROM matches WHERE id = p_match_id;
    
    -- Revertir cambios ELO anteriores
    UPDATE players 
    SET elo_rating = elo_rating - old_match.player1_elo_change
    WHERE id = old_match.player1_id;
    
    UPDATE players 
    SET elo_rating = elo_rating - old_match.player2_elo_change
    WHERE id = old_match.player2_id;
    
    -- Obtener ratings actuales (después de revertir)
    SELECT elo_rating INTO player1_rating FROM players WHERE id = old_match.player1_id;
    SELECT elo_rating INTO player2_rating FROM players WHERE id = old_match.player2_id;
    
    -- Calcular nuevos cambios ELO
    new_player1_elo_change := calculate_elo_change(
        player1_rating, 
        player2_rating, 
        p_new_winner_id = old_match.player1_id
    );
    new_player2_elo_change := -new_player1_elo_change;
    
    -- Actualizar el partido
    UPDATE matches 
    SET 
        winner_id = p_new_winner_id,
        player1_score = p_new_player1_score,
        player2_score = p_new_player2_score,
        player1_elo_change = new_player1_elo_change,
        player2_elo_change = new_player2_elo_change,
        elo_change = ABS(new_player1_elo_change)
    WHERE id = p_match_id;
    
    -- Aplicar nuevos cambios ELO
    UPDATE players 
    SET elo_rating = elo_rating + new_player1_elo_change
    WHERE id = old_match.player1_id;
    
    UPDATE players 
    SET elo_rating = elo_rating + new_player2_elo_change
    WHERE id = old_match.player2_id;
END;
$$ LANGUAGE plpgsql;

-- Función para eliminar un partido (revertir cambios ELO)
CREATE OR REPLACE FUNCTION delete_match_with_elo_revert(p_match_id INTEGER) RETURNS VOID AS $$
DECLARE
    match_data RECORD;
BEGIN
    -- Obtener datos del partido
    SELECT * INTO match_data FROM matches WHERE id = p_match_id;
    
    -- Revertir cambios ELO
    UPDATE players 
    SET 
        elo_rating = elo_rating - match_data.player1_elo_change,
        matches_played = matches_played - 1,
        matches_won = CASE 
            WHEN match_data.winner_id = match_data.player1_id THEN matches_won - 1 
            ELSE matches_won 
        END
    WHERE id = match_data.player1_id;
    
    UPDATE players 
    SET 
        elo_rating = elo_rating - match_data.player2_elo_change,
        matches_played = matches_played - 1,
        matches_won = CASE 
            WHEN match_data.winner_id = match_data.player2_id THEN matches_won - 1 
            ELSE matches_won 
        END
    WHERE id = match_data.player2_id;
    
    -- Eliminar el partido
    DELETE FROM matches WHERE id = p_match_id;
END;
$$ LANGUAGE plpgsql;
