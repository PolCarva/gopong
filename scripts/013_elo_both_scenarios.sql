-- Sistema ELO que pre-calcula ambos escenarios posibles
-- Esto permite editar partidos correctamente considerando todas las variables

-- Agregar columnas para almacenar los cambios ELO en ambos escenarios
ALTER TABLE matches 
ADD COLUMN IF NOT EXISTS player1_win_elo_change INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS player1_lose_elo_change INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS player2_win_elo_change INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS player2_lose_elo_change INTEGER DEFAULT 0;

-- Función mejorada para calcular cambio ELO considerando racha
CREATE OR REPLACE FUNCTION calculate_elo_change_with_streak(
    rating1 INTEGER,
    rating2 INTEGER,
    streak1 INTEGER,
    streak2 INTEGER,
    player1_won BOOLEAN,
    k_factor INTEGER DEFAULT 32
) RETURNS INTEGER AS $$
DECLARE
    expected_score1 DECIMAL;
    actual_score1 INTEGER;
    elo_change INTEGER;
    streak_bonus1 INTEGER;
    streak_bonus2 INTEGER;
    adjusted_k_factor INTEGER;
BEGIN
    -- Calcular probabilidad esperada para jugador 1
    expected_score1 := 1.0 / (1.0 + POWER(10.0, (rating2 - rating1) / 400.0));
    
    -- Puntaje real (1 si ganó, 0 si perdió)
    actual_score1 := CASE WHEN player1_won THEN 1 ELSE 0 END;
    
    -- Bonus por racha (máximo 10 puntos extra)
    streak_bonus1 := LEAST(streak1 * 2, 10);
    streak_bonus2 := LEAST(streak2 * 2, 10);
    
    -- Ajustar K-factor basado en diferencia de rating
    adjusted_k_factor := k_factor;
    IF ABS(rating1 - rating2) > 200 THEN
        adjusted_k_factor := k_factor + 8; -- Más cambio si hay gran diferencia
    END IF;
    
    -- Calcular cambio ELO base
    elo_change := ROUND(adjusted_k_factor * (actual_score1 - expected_score1));
    
    -- Aplicar bonus por racha
    IF player1_won THEN
        elo_change := elo_change + streak_bonus1;
    ELSE
        elo_change := elo_change - streak_bonus2;
    END IF;
    
    -- Asegurar cambio mínimo de 1 punto
    IF elo_change = 0 THEN
        elo_change := CASE WHEN player1_won THEN 1 ELSE -1 END;
    END IF;
    
    RETURN elo_change;
END;
$$ LANGUAGE plpgsql;

-- Función para pre-calcular ambos escenarios de un partido
CREATE OR REPLACE FUNCTION precalculate_match_scenarios(
    p_player1_id INTEGER,
    p_player2_id INTEGER,
    OUT player1_win_change INTEGER,
    OUT player1_lose_change INTEGER,
    OUT player2_win_change INTEGER,
    OUT player2_lose_change INTEGER
) AS $$
DECLARE
    player1_data RECORD;
    player2_data RECORD;
BEGIN
    -- Obtener datos completos de ambos jugadores
    SELECT elo_rating, current_streak INTO player1_data 
    FROM players WHERE id = p_player1_id;
    
    SELECT elo_rating, current_streak INTO player2_data 
    FROM players WHERE id = p_player2_id;
    
    -- Escenario 1: Jugador 1 gana
    player1_win_change := calculate_elo_change_with_streak(
        player1_data.elo_rating, 
        player2_data.elo_rating,
        player1_data.current_streak,
        player2_data.current_streak,
        TRUE
    );
    player2_lose_change := -player1_win_change;
    
    -- Escenario 2: Jugador 2 gana
    player2_win_change := calculate_elo_change_with_streak(
        player2_data.elo_rating, 
        player1_data.elo_rating,
        player2_data.current_streak,
        player1_data.current_streak,
        TRUE
    );
    player1_lose_change := -player2_win_change;
END;
$$ LANGUAGE plpgsql;

-- Función para agregar un partido con ambos escenarios pre-calculados
CREATE OR REPLACE FUNCTION add_match_with_both_scenarios(
    p_player1_id INTEGER,
    p_player2_id INTEGER,
    p_winner_id INTEGER,
    p_player1_score INTEGER,
    p_player2_score INTEGER
) RETURNS INTEGER AS $$
DECLARE
    scenarios RECORD;
    match_id INTEGER;
    actual_p1_change INTEGER;
    actual_p2_change INTEGER;
BEGIN
    -- Pre-calcular ambos escenarios
    SELECT * INTO scenarios FROM precalculate_match_scenarios(p_player1_id, p_player2_id);
    
    -- Determinar cambios reales basados en el ganador
    IF p_winner_id = p_player1_id THEN
        actual_p1_change := scenarios.player1_win_change;
        actual_p2_change := scenarios.player2_lose_change;
    ELSE
        actual_p1_change := scenarios.player1_lose_change;
        actual_p2_change := scenarios.player2_win_change;
    END IF;
    
    -- Insertar el partido con todos los escenarios calculados
    INSERT INTO matches (
        player1_id, player2_id, winner_id, 
        player1_score, player2_score,
        player1_elo_change, player2_elo_change,
        player1_win_elo_change, player1_lose_elo_change,
        player2_win_elo_change, player2_lose_elo_change,
        elo_change
    ) VALUES (
        p_player1_id, p_player2_id, p_winner_id,
        p_player1_score, p_player2_score,
        actual_p1_change, actual_p2_change,
        scenarios.player1_win_change, scenarios.player1_lose_change,
        scenarios.player2_win_change, scenarios.player2_lose_change,
        ABS(actual_p1_change)
    ) RETURNING id INTO match_id;
    
    -- Aplicar cambios ELO reales a los jugadores
    UPDATE players 
    SET 
        elo_rating = elo_rating + actual_p1_change,
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
        elo_rating = elo_rating + actual_p2_change,
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

-- Función para editar un partido usando los escenarios pre-calculados
CREATE OR REPLACE FUNCTION edit_match_with_scenarios(
    p_match_id INTEGER,
    p_new_winner_id INTEGER,
    p_new_player1_score INTEGER,
    p_new_player2_score INTEGER
) RETURNS VOID AS $$
DECLARE
    old_match RECORD;
    new_p1_change INTEGER;
    new_p2_change INTEGER;
    old_winner_was_p1 BOOLEAN;
    new_winner_is_p1 BOOLEAN;
BEGIN
    -- Obtener datos del partido actual
    SELECT * INTO old_match FROM matches WHERE id = p_match_id;
    
    old_winner_was_p1 := (old_match.winner_id = old_match.player1_id);
    new_winner_is_p1 := (p_new_winner_id = old_match.player1_id);
    
    -- Revertir cambios ELO anteriores
    UPDATE players 
    SET 
        elo_rating = elo_rating - old_match.player1_elo_change,
        matches_won = CASE 
            WHEN old_winner_was_p1 THEN matches_won - 1 
            ELSE matches_won 
        END,
        current_streak = CASE 
            WHEN old_winner_was_p1 THEN GREATEST(current_streak - 1, 0)
            ELSE current_streak 
        END
    WHERE id = old_match.player1_id;
    
    UPDATE players 
    SET 
        elo_rating = elo_rating - old_match.player2_elo_change,
        matches_won = CASE 
            WHEN NOT old_winner_was_p1 THEN matches_won - 1 
            ELSE matches_won 
        END,
        current_streak = CASE 
            WHEN NOT old_winner_was_p1 THEN GREATEST(current_streak - 1, 0)
            ELSE current_streak 
        END
    WHERE id = old_match.player2_id;
    
    -- Usar los escenarios pre-calculados para determinar nuevos cambios
    IF new_winner_is_p1 THEN
        new_p1_change := old_match.player1_win_elo_change;
        new_p2_change := old_match.player2_lose_elo_change;
    ELSE
        new_p1_change := old_match.player1_lose_elo_change;
        new_p2_change := old_match.player2_win_elo_change;
    END IF;
    
    -- Actualizar el partido
    UPDATE matches 
    SET 
        winner_id = p_new_winner_id,
        player1_score = p_new_player1_score,
        player2_score = p_new_player2_score,
        player1_elo_change = new_p1_change,
        player2_elo_change = new_p2_change,
        elo_change = ABS(new_p1_change)
    WHERE id = p_match_id;
    
    -- Aplicar nuevos cambios ELO
    UPDATE players 
    SET 
        elo_rating = elo_rating + new_p1_change,
        matches_won = CASE WHEN new_winner_is_p1 THEN matches_won + 1 ELSE matches_won END,
        current_streak = CASE 
            WHEN new_winner_is_p1 THEN current_streak + 1 
            ELSE 0 
        END,
        max_streak = CASE 
            WHEN new_winner_is_p1 AND current_streak + 1 > max_streak 
            THEN current_streak + 1 
            ELSE max_streak 
        END
    WHERE id = old_match.player1_id;
    
    UPDATE players 
    SET 
        elo_rating = elo_rating + new_p2_change,
        matches_won = CASE WHEN NOT new_winner_is_p1 THEN matches_won + 1 ELSE matches_won END,
        current_streak = CASE 
            WHEN NOT new_winner_is_p1 THEN current_streak + 1 
            ELSE 0 
        END,
        max_streak = CASE 
            WHEN NOT new_winner_is_p1 AND current_streak + 1 > max_streak 
            THEN current_streak + 1 
            ELSE max_streak 
        END
    WHERE id = old_match.player2_id;
END;
$$ LANGUAGE plpgsql;

-- Función para eliminar un partido usando los datos almacenados
CREATE OR REPLACE FUNCTION delete_match_with_scenarios(p_match_id INTEGER) RETURNS VOID AS $$
DECLARE
    match_data RECORD;
    winner_was_p1 BOOLEAN;
BEGIN
    -- Obtener datos del partido
    SELECT * INTO match_data FROM matches WHERE id = p_match_id;
    
    winner_was_p1 := (match_data.winner_id = match_data.player1_id);
    
    -- Revertir cambios ELO y estadísticas
    UPDATE players 
    SET 
        elo_rating = elo_rating - match_data.player1_elo_change,
        matches_played = matches_played - 1,
        matches_won = CASE 
            WHEN winner_was_p1 THEN matches_won - 1 
            ELSE matches_won 
        END,
        current_streak = CASE 
            WHEN winner_was_p1 THEN GREATEST(current_streak - 1, 0)
            ELSE current_streak 
        END
    WHERE id = match_data.player1_id;
    
    UPDATE players 
    SET 
        elo_rating = elo_rating - match_data.player2_elo_change,
        matches_played = matches_played - 1,
        matches_won = CASE 
            WHEN NOT winner_was_p1 THEN matches_won - 1 
            ELSE matches_won 
        END,
        current_streak = CASE 
            WHEN NOT winner_was_p1 THEN GREATEST(current_streak - 1, 0)
            ELSE current_streak 
        END
    WHERE id = match_data.player2_id;
    
    -- Eliminar el partido
    DELETE FROM matches WHERE id = p_match_id;
END;
$$ LANGUAGE plpgsql;
