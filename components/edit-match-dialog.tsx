"use client"

import type React from "react"

import { useState } from "react"
import { createClient } from "@/lib/supabase/client"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AlertCircle } from "lucide-react"

interface Player {
  id: string
  name: string
  points: number
  created_at: string
}

interface Match {
  id: string
  player1_id: string
  player2_id: string
  winner_id: string
  created_at: string
  player1: { name: string }
  player2: { name: string }
  winner: { name: string }
}

interface EditMatchDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onMatchUpdated: () => void
  match: Match
  players: Player[]
}

export function EditMatchDialog({ open, onOpenChange, onMatchUpdated, match, players }: EditMatchDialogProps) {
  const [player1Id, setPlayer1Id] = useState(match.player1_id)
  const [player2Id, setPlayer2Id] = useState(match.player2_id)
  const [winnerId, setWinnerId] = useState(match.winner_id)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const supabase = createClient()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!player1Id || !player2Id || !winnerId) {
      setError("Todos los campos son requeridos")
      return
    }

    if (player1Id === player2Id) {
      setError("Un jugador no puede jugar contra sí mismo")
      return
    }

    if (winnerId !== player1Id && winnerId !== player2Id) {
      setError("El ganador debe ser uno de los jugadores del partido")
      return
    }

    setLoading(true)
    setError(null)

    try {
      const { error: updateError } = await supabase
        .from("matches")
        .update({
          player1_id: player1Id,
          player2_id: player2Id,
          winner_id: winnerId,
        })
        .eq("id", match.id)

      if (updateError) throw updateError

      onMatchUpdated()
    } catch (error) {
      console.error("Error updating match:", error)
      setError("Error al actualizar el partido")
    } finally {
      setLoading(false)
    }
  }

  const handleOpenChange = (newOpen: boolean) => {
    if (!newOpen) {
      setPlayer1Id(match.player1_id)
      setPlayer2Id(match.player2_id)
      setWinnerId(match.winner_id)
      setError(null)
    }
    onOpenChange(newOpen)
  }

  // Filtrar jugadores disponibles para cada selector
  const availablePlayer2 = players.filter((p) => p.id !== player1Id)
  const availableWinners = players.filter((p) => p.id === player1Id || p.id === player2Id)

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Editar Partido</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="player1">Jugador 1</Label>
            <Select value={player1Id} onValueChange={setPlayer1Id}>
              <SelectTrigger>
                <SelectValue placeholder="Selecciona el primer jugador" />
              </SelectTrigger>
              <SelectContent>
                {players.map((player) => (
                  <SelectItem key={player.id} value={player.id}>
                    {player.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="player2">Jugador 2</Label>
            <Select value={player2Id} onValueChange={setPlayer2Id}>
              <SelectTrigger>
                <SelectValue placeholder="Selecciona el segundo jugador" />
              </SelectTrigger>
              <SelectContent>
                {availablePlayer2.map((player) => (
                  <SelectItem key={player.id} value={player.id}>
                    {player.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="winner">Ganador</Label>
            <Select value={winnerId} onValueChange={setWinnerId}>
              <SelectTrigger>
                <SelectValue placeholder="Selecciona el ganador" />
              </SelectTrigger>
              <SelectContent>
                {availableWinners.map((player) => (
                  <SelectItem key={player.id} value={player.id}>
                    {player.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {error && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => handleOpenChange(false)} disabled={loading}>
              Cancelar
            </Button>
            <Button
              type="submit"
              disabled={loading || !player1Id || !player2Id || !winnerId}
              className="bg-neutral-800 hover:bg-neutral-900"
            >
              {loading ? "Actualizando..." : "Actualizar Partido"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
