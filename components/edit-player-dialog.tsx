"use client"

import type React from "react"

import { useState } from "react"
import { createClient } from "@/lib/supabase/client"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { AlertCircle } from "lucide-react"

interface Player {
  id: string
  name: string
  points: number
  created_at: string
}

interface EditPlayerDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onPlayerUpdated: () => void
  player: Player
  existingPlayers: Player[]
}

export function EditPlayerDialog({
  open,
  onOpenChange,
  onPlayerUpdated,
  player,
  existingPlayers,
}: EditPlayerDialogProps) {
  const [name, setName] = useState(player.name)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const supabase = createClient()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!name.trim()) {
      setError("El nombre es requerido")
      return
    }

    // Verificar si el nombre ya existe (excluyendo el jugador actual)
    const nameExists = existingPlayers.some(
      (p) => p.id !== player.id && p.name.toLowerCase() === name.trim().toLowerCase(),
    )

    if (nameExists) {
      setError("Ya existe un jugador con ese nombre")
      return
    }

    setLoading(true)
    setError(null)

    try {
      const { error: updateError } = await supabase.from("players").update({ name: name.trim() }).eq("id", player.id)

      if (updateError) throw updateError

      onPlayerUpdated()
    } catch (error) {
      console.error("Error updating player:", error)
      setError("Error al actualizar el jugador")
    } finally {
      setLoading(false)
    }
  }

  const handleOpenChange = (newOpen: boolean) => {
    if (!newOpen) {
      setName(player.name)
      setError(null)
    }
    onOpenChange(newOpen)
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Editar Jugador</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="player-name">Nombre del Jugador</Label>
            <Input
              id="player-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ingresa el nombre del jugador"
              disabled={loading}
            />
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
            <Button type="submit" disabled={loading || !name.trim()} className="bg-[#7B63DB] hover:bg-[#6B53CB]">
              {loading ? "Actualizando..." : "Actualizar Jugador"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
