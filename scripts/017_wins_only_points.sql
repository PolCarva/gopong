-- ============================================
-- MODIFICAR SISTEMA DE PUNTOS
-- Ganar = +1 punto
-- Perder = 0 puntos (sin cambio)
-- ============================================

-- ============================================
-- FUNCIÓN: AGREGAR PARTIDO (ACTUALIZADA)
-- ============================================
CREATE OR REPLACE FUNCTION add_match_simple(
  p_player1_id UUID,
  p_player2_id UUID,
  p_winner_id UUID
)
RETURNS UUID AS $$
DECLARE
  v_match_id UUID;
  v_loser_id UUID;
  v_winner_current_streak INTEGER;
  v_loser_current_streak INTEGER;
BEGIN
  -- Validar que los jugadores sean diferentes
  IF p_player1_id = p_player2_id THEN
    RAISE EXCEPTION 'Los jugadores deben ser diferentes';
  END IF;

  -- Validar que el ganador sea uno de los jugadores
  IF p_winner_id != p_player1_id AND p_winner_id != p_player2_id THEN
    RAISE EXCEPTION 'El ganador debe ser uno de los jugadores del partido';
  END IF;

  -- Determinar el perdedor
  v_loser_id := CASE 
    WHEN p_winner_id = p_player1_id THEN p_player2_id 
    ELSE p_player1_id 
  END;

  -- Insertar el partido
  INSERT INTO matches (player1_id, player2_id, winner_id)
  VALUES (p_player1_id, p_player2_id, p_winner_id)
  RETURNING id INTO v_match_id;

  -- Obtener rachas actuales
  SELECT current_streak INTO v_winner_current_streak FROM players WHERE id = p_winner_id;
  SELECT current_streak INTO v_loser_current_streak FROM players WHERE id = v_loser_id;

  -- Actualizar estadísticas del GANADOR: +1 punto (sin cambio en puntos para perdedor)
  UPDATE players
  SET 
    points = points + 1,
    wins = wins + 1,
    current_streak = CASE 
      WHEN v_winner_current_streak >= 0 THEN v_winner_current_streak + 1
      ELSE 1
    END,
    max_streak = GREATEST(
      max_streak,
      CASE 
        WHEN v_winner_current_streak >= 0 THEN v_winner_current_streak + 1
        ELSE 1
      END
    )
  WHERE id = p_winner_id;

  -- Actualizar estadísticas del PERDEDOR: solo +1 derrota, SIN restar puntos
  UPDATE players
  SET 
    losses = losses + 1,
    current_streak = CASE 
      WHEN v_loser_current_streak <= 0 THEN v_loser_current_streak - 1
      ELSE -1
    END
  WHERE id = v_loser_id;

  RETURN v_match_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- FUNCIÓN: EDITAR PARTIDO (ACTUALIZADA)
-- ============================================
CREATE OR REPLACE FUNCTION edit_match_simple(
  p_match_id UUID,
  p_new_winner_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_old_winner_id UUID;
  v_player1_id UUID;
  v_player2_id UUID;
  v_old_loser_id UUID;
  v_new_loser_id UUID;
BEGIN
  -- Obtener información del partido actual
  SELECT player1_id, player2_id, winner_id
  INTO v_player1_id, v_player2_id, v_old_winner_id
  FROM matches
  WHERE id = p_match_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Partido no encontrado';
  END IF;

  -- Si el ganador no cambió, no hacer nada
  IF v_old_winner_id = p_new_winner_id THEN
    RETURN;
  END IF;

  -- Validar que el nuevo ganador sea uno de los jugadores
  IF p_new_winner_id != v_player1_id AND p_new_winner_id != v_player2_id THEN
    RAISE EXCEPTION 'El ganador debe ser uno de los jugadores del partido';
  END IF;

  -- Determinar perdedores
  v_old_loser_id := CASE 
    WHEN v_old_winner_id = v_player1_id THEN v_player2_id 
    ELSE v_player1_id 
  END;
  
  v_new_loser_id := CASE 
    WHEN p_new_winner_id = v_player1_id THEN v_player2_id 
    ELSE v_player1_id 
  END;

  -- REVERTIR cambios del ganador anterior: -1 punto, -1 victoria
  UPDATE players
  SET 
    points = points - 1,
    wins = wins - 1
  WHERE id = v_old_winner_id;

  -- REVERTIR cambios del perdedor anterior: solo -1 derrota (sin cambio en puntos)
  UPDATE players
  SET 
    losses = losses - 1
  WHERE id = v_old_loser_id;

  -- APLICAR cambios al nuevo ganador: +1 punto, +1 victoria
  UPDATE players
  SET 
    points = points + 1,
    wins = wins + 1
  WHERE id = p_new_winner_id;

  -- APLICAR cambios al nuevo perdedor: solo +1 derrota (sin cambio en puntos)
  UPDATE players
  SET 
    losses = losses + 1
  WHERE id = v_new_loser_id;

  -- Actualizar el partido
  UPDATE matches
  SET winner_id = p_new_winner_id
  WHERE id = p_match_id;

  -- Recalcular rachas para ambos jugadores
  PERFORM recalculate_streaks(v_player1_id);
  PERFORM recalculate_streaks(v_player2_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- FUNCIÓN: ELIMINAR PARTIDO (ACTUALIZADA)
-- ============================================
CREATE OR REPLACE FUNCTION delete_match_simple(
  p_match_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_winner_id UUID;
  v_loser_id UUID;
  v_player1_id UUID;
  v_player2_id UUID;
BEGIN
  -- Obtener información del partido
  SELECT player1_id, player2_id, winner_id
  INTO v_player1_id, v_player2_id, v_winner_id
  FROM matches
  WHERE id = p_match_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Partido no encontrado';
  END IF;

  -- Determinar el perdedor
  v_loser_id := CASE 
    WHEN v_winner_id = v_player1_id THEN v_player2_id 
    ELSE v_player1_id 
  END;

  -- REVERTIR cambios del ganador: -1 punto, -1 victoria
  UPDATE players
  SET 
    points = points - 1,
    wins = wins - 1
  WHERE id = v_winner_id;

  -- REVERTIR cambios del perdedor: solo -1 derrota (sin cambio en puntos)
  UPDATE players
  SET 
    losses = losses - 1
  WHERE id = v_loser_id;

  -- Eliminar el partido
  DELETE FROM matches WHERE id = p_match_id;

  -- Recalcular rachas para ambos jugadores
  PERFORM recalculate_streaks(v_player1_id);
  PERFORM recalculate_streaks(v_player2_id);
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================
DO $$
BEGIN
  RAISE NOTICE '✅ Sistema de puntos actualizado exitosamente';
  RAISE NOTICE '🎯 Nuevo sistema: Ganar = +1 punto, Perder = 0 puntos (sin cambio)';
END $$;
