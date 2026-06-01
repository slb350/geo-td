-- Wave contracts (V2-M3): an optional risk/reward the player may sign before some
-- (non-boss) waves. Signing arms a single active_contract whose RISK hits exactly
-- the next wave and whose REWARD lands only on wave clear (never on death) -- so a
-- contract is a real "greed vs safety" choice. Card metadata (risk/reward/desc) is
-- data (data/contracts.json); the lifecycle (draft -> sign/decline -> arm ->
-- grant_reward -> expire) lives here.
--
-- Risk channels: hp_mult / count_mult are read by wave.start (heavier spawns);
-- disable blacks out a random tower for the wave's opening seconds (arm); no_sell
-- gates tower.sell. Reward channels: charge / money / bank_shard (-> meta at run
-- end) / module_discount (one-shot off the next module socket).

local C = require("lib.const")
local rng = require("lib.rng")
local wave = require("lib.wave")

local DEFS = usagi.read_json("contracts.json")

local M = {}
M.DEFS = DEFS
M.ORDER = { "enrage", "swarm", "blackout", "nosell" }

-- Is a contract offered immediately before wave `w`? On the cadence, never a boss
-- wave (boss waves are exams, not negotiations).
function M.pending_for(run, w)
  return w % C.CONTRACT_EVERY == 0 and not wave.is_boss_for(run, w)
end

function M.pending(run)
  return M.pending_for(run, run.wave_index + 1)
end

local function make_card(id)
  local d = DEFS[id]
  return { id = id, name = d.name, shape = d.shape, desc = d.desc, risk = d.risk, reward = d.reward }
end

-- Draft the contracts offered before the next wave: those unlocked by min_wave,
-- shuffled with a derived rng (deterministic per seed/wave, doesn't touch the main
-- rng), capped at three.
function M.draft(run)
  local w = run.wave_index + 1
  local pool = {}
  for i = 1, #M.ORDER do
    local id = M.ORDER[i]
    if (DEFS[id].min_wave or 1) <= w then pool[#pool + 1] = id end
  end
  rng.derive(run.seed, w * 31 + 99):shuffle(pool)
  local out = {}
  for i = 1, math.min(3, #pool) do
    out[#out + 1] = make_card(pool[i])
  end
  return out
end

function M.sign(run, card)
  run.active_contract = card
  run.contract_history[#run.contract_history + 1] = card.id
end

function M.decline(run)
  run.active_contract = nil
end

-- Apply the wave-scoped risk that needs the spawned wave/towers (blackout +
-- no_sell). hp_mult / count_mult are read directly by wave.start. Called from
-- run.begin_wave after the wave is set up; a no-op without an active contract.
function M.arm(run)
  local ac = run.active_contract
  if not ac then return end
  run.no_sell = ac.risk.no_sell == true
  if ac.risk.disable and #run.towers > 0 then
    local r = rng.derive(run.seed, run.wave_index * 7 + 3)
    run.towers[r:int(1, #run.towers)].disabled_t = ac.risk.disable
  end
end

-- Grant the active contract's reward. Called ONLY on wave clear (not on death).
function M.grant_reward(run)
  local ac = run.active_contract
  if not ac then return end
  local rw = ac.reward
  if rw.charge then run.charge = run.charge + rw.charge end
  if rw.money then run.money = run.money + rw.money end
  if rw.bank_shard then run.bank_shards = run.bank_shards + rw.bank_shard end
  if rw.module_discount then run.module_discount = (run.module_discount or 0) + rw.module_discount end
end

-- Clear the active contract + its wave-scoped flags (after the reward is granted).
function M.expire(run)
  run.active_contract = nil
  run.no_sell = false
end

return M
