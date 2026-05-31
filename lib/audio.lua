-- Scene-aware music director with per-state track pools. set(state) keeps the
-- current track playing while the state is unchanged, and on each *change* of
-- state advances that state's rotation to the next track in its pool -- so the
-- soundtrack varies across a run (combat cycles after every boss; the boss
-- theme alternates) instead of looping one clip. The current state + its
-- per-state rotation index live on the global State so a live reload never
-- restarts the song. All calls no-op safely if music/<track>.* is absent.

local settings = require("lib.settings")

local M = {}

-- The out-of-the-box music level is the music_vol setting's default (0.48). The
-- live value is read at each track change so a volume change takes effect on the
-- next track; a missing State.settings falls back to that default.

-- Tracks per scene-state, played in rotation. Boss is the cinematic / female
-- synthwave set; combat cycles the darksynth variants.
local POOL = {
  menu   = { "menu" },
  combat = { "combat", "combat2", "combat3", "combat4", "combat5" },
  boss   = { "boss", "boss2", "boss3" },
}

function M.set(state)
  if not State or State.music_state == state then return end
  State.music_state = state
  local pool = POOL[state] or { state }
  local idx = State.music_idx or {}
  local n = (idx[state] or 0) % #pool + 1   -- advance, wrapping
  idx[state] = n
  State.music_idx = idx
  music.stop()
  -- music.play_ex(name, vol, pitch, pan, loop)
  music.play_ex(pool[n], settings.value("music_vol"), 1, 0, true)
end

-- A one-shot sting layered over the running music (does NOT touch the music
-- director's state/rotation), used for dramatic beats like a boss phase change.
-- sfx.play no-ops on an absent clip, so this is safe before music/sfx assets
-- exist; add a `boss_phase` (or similarly named) clip to give it sound.
function M.stinger(name)
  sfx.play_ex(name, settings.value("sfx_vol"), 1, 0)
end

function M.stop()
  if State then State.music_state = nil end
  music.stop()
end

return M
