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
  id: number
  name: string
  points?: number
  elo_rating?: number
  current_streak?: number
  max_streak?: number
  created_at: string
}

interface AddMatchDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onMatchAdded: () => void
  players: Player[]
}

export function AddMatchDialog({ open, onOpenChange, onMatchAdded, players }: AddMatchDialogProps) {
  const [player1Id, setPlayer1Id] = useState<number | null>(null)
  const [player2Id, setPlayer2Id] = useState<number | null>(null)
  const [winnerId, setWinnerId] = useState<number | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const supabase = createClient()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    console.log("[v0] Form submitted with:", { player1Id, player2Id, winnerId })

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
      const player1Score = winnerId === player1Id ? 1 : 0
      const player2Score = winnerId === player2Id ? 1 : 0

      console.log("[v0] Inserting match with automatic scores:", { player1Score, player2Score })

      const { error: insertError } = await supabase.from("matches").insert([
        {
          player1_id: player1Id,
          player2_id: player2Id,
          winner_id: winnerId,
          player1_score: player1Score,
          player2_score: player2Score,
        },
      ])

      if (insertError) {
        console.log("[v0] Insert error:", insertError)
        throw insertError
      }

      console.log("[v0] Match inserted successfully")
      resetForm()
      onMatchAdded()
    } catch (error) {
      console.error("Error adding match:", error)
      setError("Error al agregar el partido")
    } finally {
      setLoading(false)
    }
  }

  const resetForm = () => {
    setPlayer1Id(null)
    setPlayer2Id(null)
    setWinnerId(null)
    setError(null)
  }

  const handleOpenChange = (newOpen: boolean) => {
    if (!newOpen) {
      resetForm()
    }
    onOpenChange(newOpen)
  }

  const handlePlayer1Change = (value: string) => {
    const playerId = Number.parseInt(value, 10)
    console.log("[v0] Player 1 selected:", playerId)
    setPlayer1Id(playerId)
    if (winnerId === player1Id || winnerId === player2Id) {
      setWinnerId(null)
    }
  }

  const handlePlayer2Change = (value: string) => {
    const playerId = Number.parseInt(value, 10)
    console.log("[v0] Player 2 selected:", playerId)
    setPlayer2Id(playerId)
    if (winnerId === player1Id || winnerId === player2Id) {
      setWinnerId(null)
    }
  }

  const handleWinnerChange = (value: string) => {
    const playerId = Number.parseInt(value, 10)
    console.log("[v0] Winner selected:", playerId)
    setWinnerId(playerId)
  }

  const availablePlayer2 = players.filter((p) => p.id !== player1Id)
  const availableWinners = players.filter((p) => p.id === player1Id || p.id === player2Id)

  console.log("[v0] Available players:", {
    total: players.length,
    player1Id,
    player2Id,
    winnerId,
    availablePlayer2: availablePlayer2.length,
    availableWinners: availableWinners.length,
  })

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Agregar Nuevo Partido</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="player1">Jugador 1</Label>
            <Select value={player1Id?.toString() || ""} onValueChange={handlePlayer1Change}>
              <SelectTrigger>
                <SelectValue placeholder="Selecciona el primer jugador" />
              </SelectTrigger>
              <SelectContent>
                {players.map((player) => (
                  <SelectItem key={player.id} value={player.id.toString()}>
                    {player.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="player2">Jugador 2</Label>
            <Select value={player2Id?.toString() || ""} onValueChange={handlePlayer2Change}>
              <SelectTrigger>
                <SelectValue placeholder="Selecciona el segundo jugador" />
              </SelectTrigger>
              <SelectContent>
                {availablePlayer2.map((player) => (
                  <SelectItem key={player.id} value={player.id.toString()}>
                    {player.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="winner">Ganador</Label>
            <Select value={winnerId?.toString() || ""} onValueChange={handleWinnerChange}>
              <SelectTrigger>
                <SelectValue placeholder="Selecciona el ganador" />
              </SelectTrigger>
              <SelectContent>
                {availableWinners.map((player) => (
                  <SelectItem key={player.id} value={player.id.toString()}>
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
              {loading ? "Agregando..." : "Agregar Partido"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
