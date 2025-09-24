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
  id: number // Changed from string to number to match database
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
  const [player1Score, setPlayer1Score] = useState<number>(0)
  const [player2Score, setPlayer2Score] = useState<number>(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const supabase = createClient()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    console.log("[v0] Form submitted with:", { player1Id, player2Id, winnerId, player1Score, player2Score })

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

    if (player1Score < 0 || player2Score < 0) {
      setError("Los puntajes no pueden ser negativos")
      return
    }

    if (player1Score === player2Score) {
      setError("No puede haber empates en ping pong")
      return
    }

    if (
      (winnerId === player1Id && player1Score <= player2Score) ||
      (winnerId === player2Id && player2Score <= player1Score)
    ) {
      setError("El ganador debe tener el puntaje más alto")
      return
    }

    setLoading(true)
    setError(null)

    try {
      console.log("[v0] Inserting match...")
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
    setPlayer1Score(0)
    setPlayer2Score(0)
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

  const handlePlayer1ScoreChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const score = Number.parseInt(e.target.value, 10) || 0
    setPlayer1Score(score)
    console.log("[v0] Player 1 score:", score)
  }

  const handlePlayer2ScoreChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const score = Number.parseInt(e.target.value, 10) || 0
    setPlayer2Score(score)
    console.log("[v0] Player 2 score:", score)
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

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="player1Score">
                Puntaje {players.find((p) => p.id === player1Id)?.name || "Jugador 1"}
              </Label>
              <input
                id="player1Score"
                type="number"
                min="0"
                value={player1Score}
                onChange={handlePlayer1ScoreChange}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                placeholder="0"
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="player2Score">
                Puntaje {players.find((p) => p.id === player2Id)?.name || "Jugador 2"}
              </Label>
              <input
                id="player2Score"
                type="number"
                min="0"
                value={player2Score}
                onChange={handlePlayer2ScoreChange}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
                placeholder="0"
              />
            </div>
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
