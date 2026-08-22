RM = RM or {}

RM.VERSION = "0.2.0-phase1"

RM.config = {
  nameMinLen  = 3,
  nameMaxLen  = 20,
  namePattern = "^[%w_%-%. ]+$",

  -- guests have no stable BeamMP id, so nothing they do can be attributed
  -- across sessions. set AllowGuests = false in ServerConfig.toml to drop the case.
  guestsRanked = false,

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

  penalties = { recovery = 60.0, flatTire = 30.0, repair = 30.0 },
  holds     = { spareTire = 30.0, repair = 60.0, fuel = 20.0 },

  speedZoneMph = 37,
  xpCurve      = { first = 200, step = 2, floor = 20 },

  maxCheckpoints = 200,
  maxTracks      = 64,
  maxPerfRuns    = 200,

  discordUrl = "https://discord.gg/CHANGEME",
}

-- what the client is allowed to see
RM.config.public = {
  version       = RM.VERSION,
  penalties     = RM.config.penalties,
  holds         = RM.config.holds,
  speedZoneMph  = RM.config.speedZoneMph,
  discordUrl    = RM.config.discordUrl,
  nameMinLen    = RM.config.nameMinLen,
  nameMaxLen    = RM.config.nameMaxLen,
  maxCheckpoints = RM.config.maxCheckpoints,
}
