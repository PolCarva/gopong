"use client"

import { useState, useEffect } from "react"
import { createClient } from "@/lib/supabase/client"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Trophy, Users, Plus, Calendar, Edit, Trash2, TrendingUp, Flame } from "lucide-react"
import { AddPlayerDialog } from "./add-player-dialog"
import { AddMatchDialog } from "./add-match-dialog"
import { EditPlayerDialog } from "./edit-player-dialog"
import { EditMatchDialog } from "./edit-match-dialog"

interface Player {
  id: string
  name: string
  points: number
  elo_rating?: number
  current_streak?: number
  max_streak?: number
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

export function GoPongApp() {
  const [players, setPlayers] = useState<Player[]>([])
  const [matches, setMatches] = useState<Match[]>([])
  const [loading, setLoading] = useState(true)
  const [showAddPlayer, setShowAddPlayer] = useState(false)
  const [showAddMatch, setShowAddMatch] = useState(false)
  const [editingPlayer, setEditingPlayer] = useState<Player | null>(null)
  const [editingMatch, setEditingMatch] = useState<Match | null>(null)

  const supabase = createClient()

  const fetchData = async () => {
    try {
      console.log("[v0] Fetching players data...")

      // Primero verificar qué columnas existen
      const { data: playersData, error: playersError } = await supabase.from("players").select("*").order("name")

      if (playersError) {
        console.log("[v0] Players error:", playersError)
        throw playersError
      }

      console.log("[v0] Players data received:", playersData)

      // Ordenar por ELO si existe, sino por puntos
      const sortedPlayers = playersData || []
      if (sortedPlayers.length > 0) {
        if ("elo_rating" in sortedPlayers[0]) {
          sortedPlayers.sort((a, b) => (b.elo_rating || 1200) - (a.elo_rating || 1200))
        } else if ("points" in sortedPlayers[0]) {
          sortedPlayers.sort((a, b) => (b.points || 0) - (a.points || 0))
        }
      }

      // Obtener partidos con información de jugadores
      const { data: matchesData, error: matchesError } = await supabase
        .from("matches")
        .select(`
          *,
          player1:players!matches_player1_id_fkey(name),
          player2:players!matches_player2_id_fkey(name),
          winner:players!matches_winner_id_fkey(name)
        `)
        .order("created_at", { ascending: false })

      if (matchesError) {
        console.log("[v0] Matches error:", matchesError)
        throw matchesError
      }

      console.log("[v0] Matches data received:", matchesData)

      setPlayers(sortedPlayers)
      setMatches(matchesData || [])
    } catch (error) {
      console.error("Error fetching data:", error)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchData()
  }, [])

  const handlePlayerAdded = () => {
    fetchData()
    setShowAddPlayer(false)
  }

  const handleMatchAdded = () => {
    fetchData()
    setShowAddMatch(false)
  }

  const handlePlayerUpdated = () => {
    fetchData()
    setEditingPlayer(null)
  }

  const handleMatchUpdated = () => {
    fetchData()
    setEditingMatch(null)
  }

  const handleDeleteMatch = async (matchId: string) => {
    if (!confirm("¿Estás seguro de que quieres eliminar este partido?")) return

    try {
      const { error } = await supabase.from("matches").delete().eq("id", matchId)
      if (error) throw error
      fetchData()
    } catch (error) {
      console.error("Error deleting match:", error)
      alert("Error al eliminar el partido")
    }
  }

  const getStreakColor = (streak: number) => {
    if (streak >= 5) return "text-red-600 bg-red-50 border-red-200"
    if (streak >= 3) return "text-orange-600 bg-orange-50 border-orange-200"
    if (streak >= 1) return "text-green-600 bg-green-50 border-green-200"
    return "text-neutral-500 bg-neutral-50 border-neutral-200"
  }

  const getEloRank = (elo: number) => {
    if (elo >= 1800) return { rank: "Maestro", color: "text-purple-600 bg-purple-50" }
    if (elo >= 1600) return { rank: "Experto", color: "text-blue-600 bg-blue-50" }
    if (elo >= 1400) return { rank: "Avanzado", color: "text-green-600 bg-green-50" }
    if (elo >= 1200) return { rank: "Intermedio", color: "text-yellow-600 bg-yellow-50" }
    return { rank: "Principiante", color: "text-neutral-600 bg-neutral-50" }
  }

  const hasEloSystem = players.length > 0 && players[0].elo_rating !== undefined

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-[#7B63DB]"></div>
      </div>
    )
  }

  return (
    <div className="max-w-6xl mx-auto space-y-6">
      {/* Botones de acción */}
      <div className="flex gap-4 justify-center">
        <Button onClick={() => setShowAddPlayer(true)} className="bg-[#7B63DB] hover:bg-[#6B53CB] text-white">
          <Users className="w-4 h-4 mr-2" />
          Agregar Jugador
        </Button>
        <Button
          onClick={() => setShowAddMatch(true)}
          disabled={players.length < 2}
          className="bg-neutral-800 hover:bg-neutral-900 text-white"
        >
          <Plus className="w-4 h-4 mr-2" />
          Agregar Partido
        </Button>
      </div>

      {/* Tabs principales */}
      <Tabs defaultValue="ranking" className="w-full">
        <TabsList className="grid w-full grid-cols-2 bg-neutral-100 dark:bg-neutral-800">
          <TabsTrigger
            value="ranking"
            className="flex items-center gap-2 data-[state=active]:bg-[#7B63DB] data-[state=active]:text-white"
          >
            <Trophy className="w-4 h-4" />
            Ranking
          </TabsTrigger>
          <TabsTrigger
            value="history"
            className="flex items-center gap-2 data-[state=active]:bg-[#7B63DB] data-[state=active]:text-white"
          >
            <Calendar className="w-4 h-4" />
            Historial
          </TabsTrigger>
        </TabsList>

        <TabsContent value="ranking" className="space-y-4">
          <Card className="border-neutral-200 dark:border-neutral-800">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Trophy className="w-5 h-5 text-[#7B63DB]" />
                {hasEloSystem ? "Ranking ELO" : "Ranking"}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {players.length === 0 ? (
                <p className="text-center text-neutral-500 py-8">
                  No hay jugadores registrados. ¡Agrega el primer jugador!
                </p>
              ) : (
                <div className="space-y-3">
                  {players.map((player, index) => {
                    const rating = player.elo_rating || player.points || 1200
                    const eloRank = hasEloSystem ? getEloRank(rating) : null
                    const currentStreak = player.current_streak || 0
                    const maxStreak = player.max_streak || 0

                    return (
                      <div
                        key={player.id}
                        className="flex items-center justify-between p-4 rounded-lg border border-neutral-200 dark:border-neutral-700 bg-white dark:bg-neutral-800 hover:bg-neutral-50 dark:hover:bg-neutral-700 transition-colors"
                      >
                        <div className="flex items-center gap-4">
                          <div className="flex items-center justify-center w-8 h-8 rounded-full bg-[#7B63DB]/10 text-[#7B63DB] font-bold">
                            {index + 1}
                          </div>
                          <div>
                            <div className="flex items-center gap-2">
                              <h3 className="font-semibold text-neutral-900 dark:text-neutral-100">{player.name}</h3>
                              {currentStreak > 0 && (
                                <div className="flex items-center gap-1">
                                  <Flame className="w-4 h-4 text-orange-500" />
                                  <span className="text-sm font-medium text-orange-600">{currentStreak}</span>
                                </div>
                              )}
                            </div>
                            <div className="flex items-center gap-2 mt-1">
                              {hasEloSystem && eloRank && (
                                <Badge className={`text-xs px-2 py-0.5 ${eloRank.color} border`}>{eloRank.rank}</Badge>
                              )}
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <div className="text-right">
                            <Badge variant="secondary" className="text-lg px-3 py-1 bg-neutral-100 dark:bg-neutral-700">
                              {hasEloSystem ? (
                                <TrendingUp className="w-4 h-4 mr-1" />
                              ) : (
                                <Trophy className="w-4 h-4 mr-1" />
                              )}
                              {rating}
                            </Badge>
                            {hasEloSystem && maxStreak > 0 && (
                              <div className="text-xs text-neutral-500 mt-1">Mejor racha: {maxStreak}</div>
                            )}
                          </div>
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setEditingPlayer(player)}
                            className="text-neutral-600 hover:text-[#7B63DB]"
                          >
                            <Edit className="w-4 h-4" />
                          </Button>
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="history" className="space-y-4">
          <Card className="border-neutral-200 dark:border-neutral-800">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Calendar className="w-5 h-5 text-neutral-800 dark:text-neutral-200" />
                Historial de Partidos
              </CardTitle>
            </CardHeader>
            <CardContent>
              {matches.length === 0 ? (
                <p className="text-center text-neutral-500 py-8">
                  No hay partidos registrados. ¡Agrega el primer partido!
                </p>
              ) : (
                <div className="space-y-3">
                  {matches.map((match) => (
                    <div
                      key={match.id}
                      className="flex items-center justify-between p-4 rounded-lg border border-neutral-200 dark:border-neutral-700 bg-white dark:bg-neutral-800 hover:bg-neutral-50 dark:hover:bg-neutral-700 transition-colors"
                    >
                      <div className="flex items-center gap-4">
                        <div className="text-center">
                          <div className="text-sm font-medium text-neutral-900 dark:text-neutral-100">
                            {match.player1.name}
                          </div>
                          <div className="text-xs text-neutral-500">vs</div>
                          <div className="text-sm font-medium text-neutral-900 dark:text-neutral-100">
                            {match.player2.name}
                          </div>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <div className="text-center">
                          <Badge className="bg-[#7B63DB]/10 text-[#7B63DB] border-[#7B63DB]/20">
                            Ganador: {match.winner.name}
                          </Badge>
                          <div className="text-xs text-neutral-500 mt-1">
                            {new Date(match.created_at).toLocaleString()}
                          </div>
                        </div>
                        <div className="flex gap-1">
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setEditingMatch(match)}
                            className="text-neutral-600 hover:text-[#7B63DB]"
                          >
                            <Edit className="w-4 h-4" />
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => handleDeleteMatch(match.id)}
                            className="text-neutral-600 hover:text-red-600"
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Diálogos */}
      <AddPlayerDialog
        open={showAddPlayer}
        onOpenChange={setShowAddPlayer}
        onPlayerAdded={handlePlayerAdded}
        existingPlayers={players}
      />
      <AddMatchDialog
        open={showAddMatch}
        onOpenChange={setShowAddMatch}
        onMatchAdded={handleMatchAdded}
        players={players}
      />
      {editingPlayer && (
        <EditPlayerDialog
          open={!!editingPlayer}
          onOpenChange={(open) => !open && setEditingPlayer(null)}
          onPlayerUpdated={handlePlayerUpdated}
          player={editingPlayer}
          existingPlayers={players}
        />
      )}
      {editingMatch && (
        <EditMatchDialog
          open={!!editingMatch}
          onOpenChange={(open) => !open && setEditingMatch(null)}
          onMatchUpdated={handleMatchUpdated}
          match={editingMatch}
          players={players}
        />
      )}
    </div>
  )
}
