UpgradableFactoriesSaveHandler = {
    xmlFilename = nil
}


function UpgradableFactoriesSaveHandler:init(newSavegame)
		if not newSavegame then
			self.xmlFilename = g_currentMission.missionInfo.savegameDirectory .. "/upgradableFactories.xml"
		end

        self:initSchema()

		self:loadXML()
end

function UpgradableFactoriesSaveHandler:initSchema()
    self.basePath = "upgradableFactories"
    self.xmlSchema = XMLSchema.new(self.basePath)

	UFInfo("Created savegame schema and set basePath to %s", self.basePath)

    local productionEntry = ".production(?)"
    local filltypeEntry = ".fillLevels.fillType(?)"

    self.xmlSchema:register(XMLValueType.INT, self.basePath .. "#maxLevel", "Maximum Production Level", 10, true)
    
    self.xmlSchema:register(XMLValueType.INT, self.basePath .. productionEntry .. "#id", "Production ID", nil, true)
    self.xmlSchema:register(XMLValueType.INT, self.basePath .. productionEntry .. "#farmId", "Owner Farm ID", nil, true)
    self.xmlSchema:register(XMLValueType.STRING, self.basePath .. productionEntry .. "#name", "Production Point Name", nil, false) --nice to have for readability, but not actually loaded from save
    self.xmlSchema:register(XMLValueType.INT, self.basePath .. productionEntry .. "#level", "Production Level", 1, true)
    self.xmlSchema:register(XMLValueType.INT, self.basePath .. productionEntry .. "#basePrice", "Production Base Price", nil, true)
    self.xmlSchema:register(XMLValueType.INT, self.basePath .. productionEntry .. "#totalValue", "Production Total Value", nil, true)
    
	self.xmlSchema:register(XMLValueType.VECTOR_TRANS, self.basePath .. productionEntry .. "#position", "Production Coordinates", nil, true)
    
    self.xmlSchema:register(XMLValueType.STRING, self.basePath .. productionEntry .. filltypeEntry .. "#fillType", "Fill Type name", nil, true)
    self.xmlSchema:register(XMLValueType.INT, self.basePath .. productionEntry .. filltypeEntry .. "#fillLevel", "Fill Level", 0, true)

	UFInfo("Finished schema entry registration.")
end

--This code can be adapted to sync all current productions to a connecting client.
function UpgradableFactoriesSaveHandler.saveToXML()
	UFInfo("Saving to XML")
	-- on a new save, create xmlFile path
	if g_currentMission.missionInfo.savegameDirectory then
		UpgradableFactoriesSaveHandler.xmlFilename = g_currentMission.missionInfo.savegameDirectory .. "/upgradableFactories.xml"
	end
	
	UFInfo("Calling XMLFile.create with %s; %s; %s; %s", "UpgradableFactoriesXML", UpgradableFactoriesSaveHandler.xmlFilename, UpgradableFactoriesSaveHandler.basePath, UpgradableFactoriesSaveHandler.xmlSchema)
	local xmlFile = XMLFile.create("UpgradableFactoriesXML", UpgradableFactoriesSaveHandler.xmlFilename, UpgradableFactoriesSaveHandler.basePath, UpgradableFactoriesSaveHandler.xmlSchema)
	xmlFile:setValue("upgradableFactories#maxLevel", UpgradableFactories.MAX_LEVEL)
	
	-- check if the game has any farmIds that have productions
	if #g_currentMission.productionChainManager.farmIds > 0 then
		local idx = 0
		-- iterate over all (player-)farmIDs and their productions
		-- needs to use pairs() and not ipairs() since ipairs stops when an id is missing (as in: a farm has no productions)
		for farmId,farmTable in pairs(g_currentMission.productionChainManager.farmIds) do
			if tonumber(farmId) ~= nil then
				if farmId ~= nil and farmId ~= FarmlandManager.NO_OWNER_FARM_ID and farmId ~= FarmManager.INVALID_FARM_ID then
					local prodpoints = farmTable.productionPoints
					for _,prodpoint in pairs(prodpoints) do
						if prodpoint.isUpgradable then
							local key = string.format("upgradableFactories.production(%d)", idx)
							xmlFile:setValue(key .. "#id", idx+1) --printed id is 1-indexed, but xml element access is 0-indexed
							xmlFile:setValue(key .. "#farmId", farmId)
							xmlFile:setValue(key .. "#name", prodpoint.baseName)
							xmlFile:setValue(key .. "#level", prodpoint.productionLevel)
							xmlFile:setValue(key .. "#basePrice", prodpoint.owningPlaceable.price)
							xmlFile:setValue(key .. "#totalValue", prodpoint.owningPlaceable.totalValue)
							xmlFile:setValue(key .. "#position", prodpoint.owningPlaceable:getPosition())
							
							local j = 0
							key2 = ""
							for ft,val in pairs(prodpoint.storage.fillLevels) do
								key2 = key .. string.format(".fillLevels.fillType(%d)", j)
								xmlFile:setValue(key2 .. "#fillType", g_fillTypeManager:getFillTypeNameByIndex(ft))
								xmlFile:setValue(key2 .. "#fillLevel", val)
								j = j + 1
							end
							idx = idx+1
						end
					end
				end
			end
		end
		
	end
	xmlFile:save()
end

function UpgradableFactoriesSaveHandler:loadXML()
	UFInfo("Loading XML...")
	
	if not self.xmlFilename then
		UFInfo("New savegame")
		return
	end
	
	UFInfo("Try load savegame at path %s with schema %s", self.xmlFilename, self.xmlSchema.name)
	local xmlFile = XMLFile.loadIfExists("UpgradableFactoriesXML", self.xmlFilename, self.xmlSchema)
	if not xmlFile then
		UFInfo("No XML file found")
		return
	end
	
	local counter = 0
	while true do
		local key = string.format(self.basePath .. ".production(%d)", counter)
		
		if not xmlFile:getValue(key .. "#id") then break end

		local x, y, z = xmlFile:getValue(key .. "#position")
		
		table.insert(
			UpgradableFactories.loadedProductions,
			{
				level = xmlFile:getValue(key .. "#level", 1),
				farmId = xmlFile:getValue(key .. "#farmId", 1),
				name = xmlFile:getValue(key .. "#name"),
				basePrice = xmlFile:getValue(key .. "#basePrice"),
				position = {
					x = x,
					y = y,
					z = z
				}
			}
		)
		
		local fillLevels = {}
		local counter2 = 0
		while true do
			local key2 = key .. string.format(".fillLevels.fillType(%d)", counter2)
			
			local fillTypeName = xmlFile:getValue(key2 .. "#fillType")
			if not fillTypeName then 
				break 
			end
			
			local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(fillTypeName)
			fillLevels[fillTypeIndex] = xmlFile:getValue(key2 .. "#fillLevel")
			
			counter2 = counter2 +1
		end
		
		UpgradableFactories.loadedProductions[counter+1].fillLevels = fillLevels
		
		counter = counter +1
	end

	local maxLevel = xmlFile:getValue("upgradableFactories#maxLevel")
	if maxLevel and maxLevel > 0 and maxLevel < 100 then
		UpgradableFactories.MAX_LEVEL = maxLevel
	end
	UFInfo(#UpgradableFactories.loadedProductions .. " productions loaded from XML")
	UFInfo("Production maximum level: " .. UpgradableFactories.MAX_LEVEL)
	if #UpgradableFactories.loadedProductions > 0 then
		for _,p in ipairs(UpgradableFactories.loadedProductions) do
			if p.level > UpgradableFactories.MAX_LEVEL then
				UFInfo("%s over max level: %d", p.name, p.level)
			end
		end
	end
end

ItemSystem.save = Utils.prependedFunction(ItemSystem.save,  UpgradableFactoriesSaveHandler.saveToXML)
