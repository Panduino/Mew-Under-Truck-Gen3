return function(mod)
  if mod.generation ~= 3 then return end

  local installed = false
  local function install()
    if installed then return true end

    local okUntamed, untamed = pcall(function() return mod:find("untamed_advanced") end)
    local engine = okUntamed and untamed and untamed.exports and untamed.exports.engine
    if type(engine) ~= "table" then
      mod.log:error("Mew Event requires Untamed Advanced")
      return false
    end

    local Field = require("src.core.game3.field")
    local Player = require("src.core.game3.player")
    local Message = require("src.ui.game3.message")
    local Choice = require("src.ui.game3.choice")
    local Dex = require("src.core.game3.dex")

    -- Keep old saves working.
    local function stateFor(session)
      session.modData = session.modData or {}
      session.modData[mod.id] = session.modData[mod.id] or {}
      local state = session.modData[mod.id]
      if not state._legacyMigrated then
        local legacy = session.modData.rtc_untamed_nationaldex_compat
        if type(legacy) == "table" and legacy.mewCaught == true then state.mewCaught = true end
        state._legacyMigrated = true
      end
      return state
    end

    -- Read the live script var.
    local function liveVar(id)
      local okSpace, Space = pcall(require, "src.core.game3.scripting.space")
      local okFlags, Flags = pcall(require, "src.core.game3.scripting.flags")
      if not okSpace or not okFlags or not Space or not Flags or not Space.store then return nil end
      local ctx = Space.vm and Space.vm.ctx or nil
      return Flags.getVar(Space.store, ctx, id)
    end

    local rawFieldInteract = Field.interact
    local function showVermilionHarborChoice(game, onSeagallop)
      Field.lock("vermillion_harbor_choice")
      Message.show("Where would you like to go?", function()
        Choice.multi({ "SEAGALLOP FERRY", "OLD S.S. ANNE DOCK", "EXIT" }, 0, function(pick)
          if pick == 0 then
            Field.unlock("vermillion_harbor_choice")
            onSeagallop()
          elseif pick == 1 then
            mod.world:warpTo("FR_SSANNE_EXTERIOR", 31, 6, "down")
            Field.unlock("vermillion_harbor_choice")
          else
            Field.unlock("vermillion_harbor_choice")
          end
        end, { left = 10, top = 5 })
      end)
      return true
    end

    -- Catch the harbor tiles after the ship leaves.
    local rawTryCoordEvents = Field.tryCoordEvents
    if not Field._mewOldDockCoordChoiceInstalled then
      local passingToSeagallop = false
      Field.tryCoordEvents = function(game, cx, cy)
        if not passingToSeagallop then
          local session = engine.Runtime and engine.Runtime.getSession and engine.Runtime.getSession()
          if session and session.map == "FR_VERMILION_CITY"
              and (cx == 22 or cx == 23) and cy == 33 and liveVar(0x407E) == 3 then
            return showVermilionHarborChoice(game, function()
              passingToSeagallop = true
              rawTryCoordEvents(game, cx, cy)
              passingToSeagallop = false
            end)
          end
        end
        return rawTryCoordEvents(game, cx, cy)
      end
      Field._mewOldDockCoordChoiceInstalled = true
    end

    if not Field._mewTruckInteractInstalled then
      Field.interact = function(game)
        local session = engine.Runtime and engine.Runtime.getSession and engine.Runtime.getSession()

        if session and session.map == "FR_VERMILION_CITY"
            and liveVar(0x407E) == 3
            and Player.cellX == 24 and Player.cellY == 32 and Player.facing == "down"
            and not Field.isLocked() then
          return showVermilionHarborChoice(game, function() rawFieldInteract(game) end)
        end

        -- Check the truck from any side.
        if session and session.map == "FR_SSANNE_EXTERIOR" and not Field.isLocked() then
          local dx, dy = 0, 0
          if Player.facing == "up" then dy = -1
          elseif Player.facing == "down" then dy = 1
          elseif Player.facing == "left" then dx = -1
          elseif Player.facing == "right" then dx = 1 end
          local tx, ty = Player.cellX + dx, Player.cellY + dy
          if tx >= 55 and tx <= 57 and ty >= 2 and ty <= 3 then
            local state = stateFor(session)
            if state.mewCaught or (session.dex and Dex.isCaught(session.dex, 151)) then
              state.mewCaught = true
              Message.show("It's an old truck.")
              return true
            end
            Field.lock("mew_truck")
            Message.show("Something is hiding under the truck!", function()
              mod.world:startWildBattle(151, 50, function()
                if session.dex and Dex.isCaught(session.dex, 151) then state.mewCaught = true end
                Field.unlock("mew_truck")
              end)
            end)
            return true
          end
        end
        return rawFieldInteract(game)
      end
      Field._mewTruckInteractInstalled = true
    end

    installed = true
    mod.log:info("Mew Event installed")
    return true
  end

  mod.events:on("game.ready", install, -40)
end
