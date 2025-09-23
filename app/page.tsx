import { GoPongApp } from "@/components/gopong-app"

export default function Home() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-neutral-50 to-neutral-100 dark:from-neutral-950 dark:to-neutral-900">
      <div className="container mx-auto px-4 py-8">
        <div className="text-center mb-8">
          <div className="flex items-center justify-center gap-3 mb-4">
            <img src="/gopong-logo.svg" alt="GoPong" className="h-8 w-auto" />
          </div>
          <h1 className="text-4xl lg:text-6xl font-bold text-neutral-900 dark:text-neutral-100 mb-2">
            Gestión de torneos de{" "}
            <span className="font-bold text-transparent bg-clip-text bg-gradient-to-b from-[#7B63DB] via-[#7B63DB]/80 to-white">
               ping pong
            </span>
          </h1>
          <p className="text-neutral-600 dark:text-neutral-400 text-lg">
            Administra jugadores, partidos y rankings de manera sencilla
          </p>
        </div>
        <GoPongApp />
      </div>
    </div>
  )
}
