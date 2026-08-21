-- manual unload mode keeps the extension alive across level loads, which is
-- exactly when the mod needs to be working.
--
-- this file is shipped at two paths because BeamNG and the BeamMP docs
-- disagree about where it lives. extensions.load is idempotent, so whichever
-- one the game picks up, loading twice costs nothing.
load("raceManager_main")
setExtensionUnloadMode("raceManager_main", "manual")
