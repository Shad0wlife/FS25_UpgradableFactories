--[[
This mod is partially based on the GPLv3-Licensed UpgradableFactories Mod for FS22 by Percedal.
As such, this mod is also uploaded under the GPLv3 License.
]]

local modDirectory = g_currentModDirectory
local modName = g_currentModName

UpgradableFactories = {
	MAX_LEVEL = 10,
	LEVEL_BONUS_CYCLES = 0.15,
	LEVEL_RUNNING_COST_DISCOUNT = 0.1,
	LEVEL_UPGRADE_PRICE_INCREASE = 0.1,
	EnvironmentExclusions = {
		
	}
}

source(modDirectory .. "UpgradableFactoriesSaveHandler.lua")
source(modDirectory .. "InGameMenuUpgradableFactories.lua")
source(modDirectory .. "UpgradeProductionEvent.lua")
source(modDirectory .. "ProductionUpgradedEvent.lua")
addModEventListener(UpgradableFactories)

function UFInfo(infoMessage, ...)
	print(string.format("  [UpgradableFactories] " .. infoMessage, ...))
end

function UpgradableFactories:loadMap()
	self.newSavegame = not g_currentMission.missionInfo.savegameDirectory or nil
	self.loadedProductions = {}
	
	if g_dedicatedServer == nil then
		UFInfo("Try init menu logic.")
		InGameMenuUpgradableFactories.initialize()
	else
		UFInfo("Dedicated Server detected. Skipping menu init.")
	end
	
	--Only server does savegame stuff
	if g_currentMission:getIsServer() then
		UFInfo("Game is Server -> Get Production levels from Savegame")
		UpgradableFactoriesSaveHandler:init(self.newSavegame)
		
		addConsoleCommand('ufMaxLevel', 'Update UpgradableFactories max level', 'updateml', self)
		g_messageCenter:subscribe(MessageType.SAVEGAME_LOADED, self.onSavegameLoaded, self)
	else
		UFInfo("Game is Client -> Get Production levels from Sync")
	end
end

function UpgradableFactories:delete()
	g_messageCenter:unsubscribeAll(self)
end




local function getProductionPointFromPosition(pos, farmId)
	if #g_currentMission.productionChainManager.farmIds < 1 then
		return nil
	end
	
	if g_currentMission.productionChainManager.farmIds[farmId] ~= nil then
		for _,prod in pairs(g_currentMission.productionChainManager.farmIds[farmId].productionPoints) do
				-- Check position x/z and y height difference as well
				local prodX, prodY, prodZ = prod.owningPlaceable:getPosition()
				if MathUtil.getPointPointDistanceSquared(pos.x, pos.z, prodX, prodZ) < 0.0001 and math.abs(pos.y - prodY) < 0.0001 then
					return prod
				end
		end
	end
	return nil
end

local function getCapacityAtLvl(capacity, level)
	-- Strorage capacity increase by it's base value each level
	return math.floor(capacity * level)
end

local function getCycleAtLvl(cycle, level, isMonthly)
	-- Production speed increase by it's base value each level.
	-- A bonus of 15% of the base speed is applied per level starting at the level 2
	-- eg. base cycles were 100, factory at lvl 3: 100*3 + 100*0.15*(3-1) = 300 + 100*0.15*2 = 300 + 30 = 330
	level = tonumber(level)
	local adj = cycle * level + cycle * UpgradableFactories.LEVEL_BONUS_CYCLES * (level - 1)
	if adj < 1 then
		return adj
	else
		if isMonthly then
			return math.floor(adj)
		else
			return math.floor(adj * 1000.0) / 1000.0
		end
	end
end

local function getActiveCostAtLvl(cost, level)
	-- Running cost increase by it's base value each level
	-- A reduction of 10% of the base cost is applied par level starting at the level 2
	level = tonumber(level)
	local adj = cost * level - cost * UpgradableFactories.LEVEL_RUNNING_COST_DISCOUNT * (level - 1)
	if adj < 1 then
		return adj
	else
		--consider rounding to 2nd digit (eg. cents) here?
		return math.floor(adj)
	end
end

local function getUpgradePriceForLvl(basePrice, level)
	-- Upgrade price increase by 10% each level
	return math.floor(basePrice + basePrice * UpgradableFactories.LEVEL_UPGRADE_PRICE_INCREASE * level)
end

local function getOverallProductionValue(basePrice, atLevel)
	-- Base price + all upgrade prices
	local value = basePrice
	for lvl=2, atLevel do
		value = value + getUpgradePriceForLvl(basePrice, lvl-1)
	end
	return value
end


-- Formats the Production UI Name to show its level
local function prodPointUFName(basename, level)
	return string.format("%d - %s", level, basename)
end


function UpgradableFactories.upgradeProductionByOne(prodpoint)
	--deduct the upgrade price from the farmId owning the placeable with the prodpoint
	g_currentMission:addMoney(-prodpoint.owningPlaceable.upgradePrice, prodpoint:getOwnerFarmId(), MoneyType.SHOP_PROPERTY_BUY, true, true)
	
	UpgradableFactories.updateProductionPointLevel(prodpoint, prodpoint.productionLevel + 1)
end

function UpgradableFactories.updateProductionPointLevel(prodpoint, lvl)
	prodpoint.productionLevel = lvl
	prodpoint.name = prodPointUFName(prodpoint.baseName, lvl)
	
	for _,prod in pairs(prodpoint.productions) do
		prod.cyclesPerMinute = getCycleAtLvl(prod.baseCyclesPerMinute, lvl)
		prod.cyclesPerHour = getCycleAtLvl(prod.baseCyclesPerHour, lvl)
		prod.cyclesPerMonth = getCycleAtLvl(prod.baseCyclesPerMonth, lvl)
		
		prod.costsPerActiveMinute = getActiveCostAtLvl(prod.baseCostsPerActiveMinute, lvl)
		prod.costsPerActiveHour = getActiveCostAtLvl(prod.baseCostsPerActiveHour, lvl)
		prod.costsPerActiveMonth = getActiveCostAtLvl(prod.baseCostsPerActiveMonth, lvl)
	end
	
	for ft,s in pairs(prodpoint.storage.baseCapacities) do
		prodpoint.storage.capacities[ft] = getCapacityAtLvl(s, lvl)
	end
	
	prodpoint.owningPlaceable.totalValue = getOverallProductionValue(prodpoint.owningPlaceable.price, lvl)
	prodpoint.owningPlaceable.upgradePrice = getUpgradePriceForLvl(prodpoint.owningPlaceable.price, lvl)
	prodpoint.owningPlaceable.getSellPrice = function ()
		local priceMultiplier = 0.75
		local maxAge = prodpoint.owningPlaceable.storeItem.lifetime
		if maxAge ~= nil and maxAge ~= 0 then
			priceMultiplier = priceMultiplier * math.exp(-3.5 * math.min(prodpoint.owningPlaceable.age / maxAge, 1))
		end
		return math.floor(prodpoint.owningPlaceable.totalValue * math.max(priceMultiplier, 0.05))
	end
	
	-- Refresh gui only on non-dedicated servers and if the updated production belongs to the own farm
	if g_dedicatedServer == nil and FSBaseMission.player ~= nil and prodpoint:getOwnerFarmId() == FSBaseMission.player.farmId then
		InGameMenuUpgradableFactories:refreshProductionPage()
	end
	
	-- broadCast event doesn't run if this is not a server, that is checked in broadcastEvent itself
	ProductionUpgradedEvent.broadcastEvent(prodpoint, lvl)
end

-- Server only
function UpgradableFactories:onSavegameLoaded()
	self:initializeLoadedProductions()
end

-- Server only
function UpgradableFactories:initializeLoadedProductions()
	if self.newSavegame or #self.loadedProductions < 1 then
		return
	end
	
	for _,loadedProd in ipairs(self.loadedProductions) do
		local prodpoint = getProductionPointFromPosition(loadedProd.position, loadedProd.farmId)
		if prodpoint then
			UFInfo("Initialize loaded production %s [is upgradable: %s]", prodpoint.baseName, prodpoint.isUpgradable)
			if prodpoint.isUpgradable then
				--prodpoint.productionLevel is set in updateProductionPointLevel
				prodpoint.owningPlaceable.price = loadedProd.basePrice
				prodpoint.owningPlaceable.totalValue = getOverallProductionValue(loadedProd.basePrice, loadedProd.level)
				
				self.updateProductionPointLevel(prodpoint, loadedProd.level)
				
				for ft,val in pairs(prodpoint.storage.fillLevels) do
					if loadedProd.fillLevels[ft] ~= nil then
						prodpoint.storage.fillLevels[ft] = loadedProd.fillLevels[ft]
					end
				end
			end
		end
	end
end

function UpgradableFactories:initializeProduction(prodpoint)
	if not prodpoint.isUpgradable then
		prodpoint.isUpgradable = true
		prodpoint.productionLevel = 1
		
		prodpoint.baseName = prodpoint:getName()
		prodpoint.name = prodPointUFName(prodpoint:getName(), 1)
		
		-- prodpoint.owningPlaceable.basePrice = prodpoint.owningPlaceable.price
		prodpoint.owningPlaceable.upgradePrice = getUpgradePriceForLvl(prodpoint.owningPlaceable.price, 1)
		prodpoint.owningPlaceable.totalValue = prodpoint.owningPlaceable.price
		
		for _,prod in pairs(prodpoint.productions) do
			prod.baseCyclesPerMinute = prod.cyclesPerMinute
			prod.baseCyclesPerHour = prod.cyclesPerHour
			prod.baseCyclesPerMonth = prod.cyclesPerMonth

			prod.baseCostsPerActiveMinute = prod.costsPerActiveMinute
			prod.baseCostsPerActiveHour = prod.costsPerActiveHour
			prod.baseCostsPerActiveMonth = prod.costsPerActiveMonth
		end
		
		prodpoint.storage.baseCapacities = {}
		for ft,val in pairs(prodpoint.storage.capacities) do
			prodpoint.storage.baseCapacities[ft] = val
		end
	end
end

function UpgradableFactories.onFinalizePlacement(placeableProduction)
	if UpgradableFactories.EnvironmentExclusions[placeableProduction.customEnvironment] ~= true then
		local spec = placeableProduction.spec_productionPoint
		local prodpoint = (spec ~= nil and spec.productionPoint) or nil
	
		if prodpoint ~= nil then
			UFInfo("Initialize production %s [has custom env: %s]", prodpoint:getName(), tostring(prodpoint.owningPlaceable.customEnvironment))
			UpgradableFactories:initializeProduction(prodpoint)
		else
			UFInfo("PlaceableProductionPoint without productionPoint is skipped...")
		end
	end
end

function UpgradableFactories.setOwnerFarmId(prodpoint, farmId, noEventSend)
	if farmId == 0 and prodpoint.productions[1].baseCyclesPerMinute then
		--productionLevel is reset to 1 in updateProductionPointLevel
		UpgradableFactories.updateProductionPointLevel(prodpoint, 1)
	end
end



function UpgradableFactories:updateml(arg)
	if not arg then
		print("ufMaxLevel <max_level>")
		return
	end
	
	local n = tonumber(arg)
	if not n then
		print("ufMaxLevel <max_level>")
		print("<max_level> must be a number")
		return
	elseif n < 1 or n > 99 then
		print("ufMaxLevel <max_level>")
		print("<max_level> must be between 1 and 99")
		return
	end
	
	self.MAX_LEVEL = n
	
	self:initializeLoadedProductions()
	
	UFInfo("Production maximum level has been updated to level "..n, "")
end




--Stream prefix functions for initial sync
function UpgradableFactories.prodpointWriteStream(prodpoint, streamId, connection)
	-- WriteStream only on connections to a client
	if not connection:getIsServer() then
		local level = prodpoint.productionLevel or 1

		streamWriteInt32(streamId, level)
	end
end

function UpgradableFactories.prodpointReadStream(prodpoint, streamId, connection)
	-- ReadStream only from connections to a server
	if connection:getIsServer() then
		local level = streamReadInt32(streamId)
		
		if prodpoint.isUpgradable then
			UpgradableFactories.updateProductionPointLevel(prodpoint, level)
		end
	end
end

--Stream patches on production point initial sync
--prepend level information before everything else, so that the levelup is executed before the storage capacities are handled
--ATTENTION: Other mods that specifically affect this sync stream need to execute their read and write exactly in order. If not, desync will occur.
ProductionPoint.readStream = Utils.prependedFunction(ProductionPoint.readStream, UpgradableFactories.prodpointReadStream)
ProductionPoint.writeStream = Utils.prependedFunction(ProductionPoint.writeStream, UpgradableFactories.prodpointWriteStream)

--Other patches
PlaceableProductionPoint.onFinalizePlacement = Utils.appendedFunction(PlaceableProductionPoint.onFinalizePlacement, UpgradableFactories.onFinalizePlacement)
ProductionPoint.setOwnerFarmId = Utils.appendedFunction(ProductionPoint.setOwnerFarmId, UpgradableFactories.setOwnerFarmId)
