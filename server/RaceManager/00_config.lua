RM = RM or {}

RM.VERSION = "0.8.0-one-board-per-race"

RM.config = {
  nameMinLen  = 3,
  nameMaxLen  = 20,
  namePattern = "^[%w_%-%. ]+$",

  -- Guests count. His whole community plays as guests, because BeamMP's
  -- registration was down for months and his own account is gone, so a
  -- guest here is a regular with a name, a level and records. The address
  -- key below is what makes them the same person tomorrow, and the recovery
  -- code covers a changed address.
  guestsRanked = true,

  -- Whether guests may join at all follows the file Bobby, their discord
  -- bot, keeps on the server for the patreon gate. When the gate is on the
  -- server is patrons only and a guest is turned away at the door with the
  -- message below. The file is read every few seconds, so Bobby's switch
  -- works live. Read as: guests are allowed when file[key] == allowedWhen;
  -- no file, or no such key, means allowed.
  guestGate = {
    file = "Resources/Server/PatreonAuth/allowed_discord_ids.json",
    key = "enabled",
    allowedWhen = false,
    everySec = 10,
  },
  guestRefusal = "Guest accounts are off right now. Log in with a BeamMP account to join.",

  -- How a guest is recognised on a later visit.
  --   "ip"   the connection, hashed. survives the new name BeamMP hands out
  --          every session, which is the only thing that works while the
  --          forum is down and nobody can register.
  --   "name" the name BeamMP gave them. a different person every join.
  -- Put this back to "name" once accounts work again: a real BeamMP id is
  -- better than an address that changes when a router reboots.
  guestKey = "ip",

  tickMs     = 100,

  -- each change of a Stella's light comes up to this log with why, so a
  -- race that showed the wrong thing can be read here. Off once it is
  -- trusted.
  stellaTrace = true,
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
  penalties = { recovery = 60.0, flatTire = 30.0, repair = 30.0, missedGate = 30.0,
                speeding = 30.0 },

  -- a run is thrown away if a lap has not been completed in this long
  raceIdleTimeoutMs = 3600000,

  -- A course that folds back on itself puts the volume for one gate a few
  -- metres from another twenty six gates away, and driving the road near the
  -- start clips the one belonging to the end of the lap. Cutting a corner
  -- skips a gate or two; it does not skip twenty six. Anything past this is a
  -- volume that was brushed rather than a gate that was driven through, so it
  -- is ignored rather than priced.
  maxGateSkip = 50,  -- each skipped gate still gets its own missed_gate penalty

  -- nothing on wheels does this, so a split implying it is a lie
  maxPlausibleMph = 300,

  -- how often the client is expected to report speed/g-force/damage/distance
  -- during a non-lap-time challenge attempt. Used only as the plausibility
  -- ceiling on a single distance sample (top speed times this many seconds);
  -- the client's own send interval is what actually decides the cadence.
  telemetryIntervalSec = 1.5,

  -- how far a client stamp may sit outside what the server believes
  clockTrustMs = 2000,
  -- how long the car is held still while each job is done. only inside a run.
  holds     = { reposition = 5.0, spareTire = 30.0, repair = 60.0, fuel = 20.0,
                rerack = 30.0 },

  -- how many spare changes a car gets before it has to pit. nil means
  -- however many tires are actually on its rack, which is what he asked
  -- for: a truck with two spares gets two, one with none gets none.
  spareChanges = nil,

  -- a quarter of a tank per press
  fuelStep  = 0.25,

  -- the default limit offered when you add a zone, and how long you have to
  -- stay over it before it costs you. one bump over a crest is free.
  speedZoneMph   = 37,
  speedGraceSec  = 3.0,
  -- what a finish pays by place. two hundred for the win, two less each
  -- place after, never under the floor. Levels grow: 750 / 1,750 / 3,000…
  xpCurve      = { first = 200, step = 2, floor = 20 },

  -- a flat bonus for finishing at all, on top of the placement curve above
  -- (races) or the ladder (challenges) -- every driver who completes a run
  -- gets this, win or last place, tier one or outside the ladder entirely.
  raceCompletionXp = 10,

  -- a challenge's ladder pays every attempt, not only the first one --
  -- but less each repeat: this fraction of the previous payout, compounding.
  -- 0.9 = 100% the first time, 90% the second, 81% the third, and so on
  -- until it floors to nothing, at which point the challenge still runs
  -- (for the tier itself and the leaderboard), just not for further XP.
  challengeRepeatDecay = 0.9,
  xpPerLevel   = 1000, -- unused; kept so older configs still load

  -- The race classes, as he sent them on 2026-09-04, in his order.
  --
  -- A class is entered, not worked out from the car: he runs every vehicle,
  -- and two people in the same truck can be in different classes. So the
  -- driver picks one when they arm, and the books sort on what was entered.
  --
  -- The optional cars list is the other way round, for the day he wants a
  -- class pinned to particular vehicles. Empty means anybody may enter it.
  --   { division = "Unlimited", name = "Trophy Truck", cars = { "pickup" } }
  classes = {
    { division = "Limited",   name = "Class 10" },
    { division = "Limited",   name = "Class 12" },
    { division = "Limited",   name = "Class 5" },
    { division = "Limited",   name = "Class 7 Stock" },
    { division = "Limited",   name = "UTV Pro Turbo" },
    { division = "Limited",   name = "UTV Pro NA" },
    { division = "Limited",   name = "UTV Pro Open" },
    { division = "Limited",   name = "Class 5/1600, 1600 & Class 9" },
    { division = "Limited",   name = "Class 11" },
    { division = "Limited",   name = "Trophy Truck Spec" },
    { division = "Limited",   name = "1450" },
    { division = "Limited",   name = "Class 2000" },
    { division = "Unlimited", name = "Class 1" },
    { division = "Unlimited", name = "Class 6200" },
    { division = "Unlimited", name = "Class 7 Unlimited" },
    { division = "Unlimited", name = "Class 8" },
    { division = "Unlimited", name = "Trophy Truck" },
  },


  -- The Stella box on the dash. How close a car has to be to ask the one in
  -- front to let it by, how long that driver has to answer, how long the
  -- green light lasts, and how far a stopped car's warning reaches.
  stella = { passWindowM = 300, passReplySecs = 30, passGoSecs = 20,
             hazardRangeM = 250 },

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
  fuelStep      = RM.config.fuelStep,
  speedZoneMph  = RM.config.speedZoneMph,
  speedGraceSec = RM.config.speedGraceSec,
  discordUrl    = RM.config.discordUrl,
  nameMinLen    = RM.config.nameMinLen,
  nameMaxLen    = RM.config.nameMaxLen,
  maxCheckpoints = RM.config.maxCheckpoints,
  classes       = RM.config.classes,
}
