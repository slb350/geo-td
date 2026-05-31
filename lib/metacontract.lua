-- Meta-contract board (V2-M7): durable goals that outlast the three shop unlocks.
-- A board holds up to BOARD_SIZE uncompleted goals; finishing a run evaluates each
-- against that run's REPORT (lib/report.build) -- never a duplicated counter -- and
-- a satisfied goal pays bank shards + a badge, is marked done forever, and is
-- replaced from the pool. Each goal is pure data: a list of {stat, op, value}
-- conditions over report fields (op "gte" for numbers, "eq" for exact/boolean/map/
-- mode matches). Persistence (meta.save) is the caller's job, like lib/mastery.

local DEFS = usagi.read_json("contracts_meta.json")

local M = {}
M.DEFS = DEFS
M.BOARD_SIZE = 3

-- Stable pool order, used to deterministically fill the board.
M.ORDER = {
  "first_blood", "boss_trio", "centurion", "broker",
  "affix_breaker", "arena_wrecker", "chicane_climb", "ironclad", "lattice_seen",
}

-- Does a run report satisfy every condition of a goal?
function M.check(def, report)
  local req = def.require
  for i = 1, #req do
    local c = req[i]
    local v = report[c.stat]
    if c.op == "gte" then
      if type(v) ~= "number" or v < c.value then return false end
    elseif c.op == "eq" then
      if v ~= c.value then return false end
    else
      return false
    end
  end
  return true
end

-- Top up meta.contract_board to BOARD_SIZE from the pool, in ORDER, skipping goals
-- already completed or already on the board. Idempotent; returns the board.
function M.refresh(meta)
  local board = meta.contract_board or {}
  local present = {}
  for i = 1, #board do present[board[i]] = true end
  local completed = meta.completed_contracts or {}
  for i = 1, #M.ORDER do
    if #board >= M.BOARD_SIZE then break end
    local id = M.ORDER[i]
    if not completed[id] and not present[id] then
      board[#board + 1] = id
      present[id] = true
    end
  end
  meta.contract_board = board
  return board
end

-- Evaluate a finished run's report against the board: pay out + retire every
-- satisfied goal, then refill. Mutates meta (currency/badges/board/completed);
-- the caller persists. Returns the list of completed goal ids (for the gameover UI).
function M.evaluate(meta, report)
  meta.completed_contracts = meta.completed_contracts or {}
  meta.badges = meta.badges or {}
  meta.bank_shards = meta.bank_shards or 0
  local board, keep, done = meta.contract_board or {}, {}, {}
  for i = 1, #board do
    local id = board[i]
    local def = DEFS[id]
    if def and M.check(def, report) then
      meta.completed_contracts[id] = true
      meta.bank_shards = meta.bank_shards + (def.shards or 0)
      if def.badge then meta.badges[def.badge] = true end
      done[#done + 1] = id
    else
      keep[#keep + 1] = id
    end
  end
  meta.contract_board = keep
  M.refresh(meta)
  return done
end

return M
