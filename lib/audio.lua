-- Scene-aware music director. Switches the looping background track only when
-- the requested track actually changes, so re-entering a scene (or a live
-- reload) never restarts the song. The current track is held on the global
-- State so it survives Usagi's live reload (file-scope locals reset; State
-- does not). All calls no-op safely if the matching music/<track>.* is absent.

local M = {}

local VOL = 0.4

function M.set(track)
  if not State or State.music_track == track then return end
  State.music_track = track
  music.stop()
  -- music.play_ex(name, vol, pitch, pan, loop)
  music.play_ex(track, VOL, 1, 0, true)
end

function M.stop()
  if State then State.music_track = nil end
  music.stop()
end

return M
