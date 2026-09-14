-- manual unload mode keeps the extension alive across level loads, which is
-- exactly when the mod needs to be working.
--
-- this file is shipped at two paths because BeamNG and the BeamMP docs
-- disagree about where it lives. extensions.load is idempotent, so whichever
-- one the game picks up, loading twice costs nothing.
load("raceManager_main")
setExtensionUnloadMode("raceManager_main", "manual")

-- The Stella instrument is its own extension, the way its author shipped it.
-- It is loaded here rather than folded into Race Manager so his updates drop
-- straight in, and so it keeps working on its own if Race Manager is off.
