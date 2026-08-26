RM = RM or {}

RM.VERSION = "0.2.0-phase2"

RM.config = {
  nameMinLen  = 3,
  nameMaxLen  = 20,
  namePattern = "^[%w_%-%. ]+$",

  -- guests have no stable BeamMP id, so nothing they do can be attributed
  -- across sessions. set AllowGuests = false in ServerConfig.toml to drop the case.
  guestsRanked = false,

  -- How a guest is recognised on a later visit.
  --   "ip"   the connection, hashed. survives the new name BeamMP hands out
  --          every session, which is the only thing that works while the
  --          forum is down and nobody can register.
  --   "name" the name BeamMP gave them. a different person every join.
  -- Put this back to "name" once accounts work again: a real BeamMP id is
  -- better than an address that changes when a router reboots.
  guestKey = "ip",

  tickMs     = 100,
  rosterMs   = 500,
  autosaveMs = 30000,

  -- A first join downloads the map before the mod can say anything, and that
  -- is minutes on a big one. Only worth complaining well after that.
  helloTimeoutMs = 600000,

  -- roster gates. a row only goes out when one of these actually moves.
  speedDeltaMph = 2,
  pingDeltaMs   = 10,

  -- outbound queue depth per player, and inbound limits per player
  maxBatchMsgs  = 24,
  maxInboundMsgs = 16,
  inboundPerSec  = 40,

  roles  = { owner = 4, admin = 3, staff = 2, player = 1 },

  -- identity keys, e.g. "beammp:12345". empty means nobody is owner until you
  -- run "rm owner <name>" in the host console, which only you can reach.
  owners = {},

  -- his document names every penalty except this one, so it is a guess until
  -- he says otherwise. flagged in the phase 2 plan.
  penalties = { recovery = 60.0, flatTire = 30.0, repair = 30.0, missedGate = 30.0 },

  -- a run is thrown away if nobody crosses anything for this long
  raceIdleTimeoutMs = 900000,

  -- nothing on wheels does this, so a split implying it is a lie
  maxPlausibleMph = 300,

  -- how far a client stamp may sit outside what the server believes
  clockTrustMs = 2000,
  holds     = { spareTire = 30.0, repair = 60.0, fuel = 20.0 },

  speedZoneMph = 37,
  xpCurve      = { first = 200, step = 2, floor = 20 },

  maxCheckpoints = 200,
  maxTracks      = 64,
  maxPerfRuns    = 200,

  -- Baja Sim's own server, given to us on 2026-08-25. The button tries the
  -- browser, but that binding is a no-op in some builds and a fullscreen game
  -- swallows the window anyway, so the panel shows the invite to copy. That is
  -- the part that always works.
  discordUrl = "https://discord.gg/7JHKJbHNt",
}

-- what the client is allowed to see
RM.config.public = {
  version       = RM.VERSION,
  penalties     = RM.config.penalties,
  maxCheckpointsPerLap = RM.config.maxCheckpoints,
  holds         = RM.config.holds,
  speedZoneMph  = RM.config.speedZoneMph,
  discordUrl    = RM.config.discordUrl,
  nameMinLen    = RM.config.nameMinLen,
  nameMaxLen    = RM.config.nameMaxLen,
  maxCheckpoints = RM.config.maxCheckpoints,
}
