local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local HttpService = game:GetService('HttpService')

local EventClass = require(script.Event)
local TableUtility = require(script.Table)

local Libraries = require(script.Parent.Parent.Libraries)
local Bridge = Libraries.RNet.Create("ReplicatedData")

local RemoteEnums = { Set = 1, Remove = 2, }

-- // Module // --
local Module = {}

Module.OnAdded = EventClass.New()
Module.OnUpdated = EventClass.New()
Module.OnRemoved = EventClass.New()

if RunService:IsServer() then

	Module.Comparison = { Public = {}, Private = {} }
	Module.Replications = { Public = {}, Private = {}, }
	Module.ReplicationKeyBlacklist = { "Tags" }

	local function CheckComparisonUpdate( category, data, uuid )
		local newCacheString = HttpService:JSONEncode(data)
		local cacheIndex = uuid or category

		local cachingTable = uuid and Module.Comparison.Private or Module.Comparison.Public
		local currentCachedString = cachingTable and cachingTable[cacheIndex]
		if (not currentCachedString) or (newCacheString ~= currentCachedString) then
			cachingTable[cacheIndex] = newCacheString
			return true
		end

		return false
	end

	local function SendDataToPlayers( category : string, data : any, playerList : { Player }? )
		-- remove blacklisted items
		data = TableUtility.DeepCopy(data)
		for _, key in ipairs( Module.ReplicationKeyBlacklist ) do
			data[key] = nil
		end

		-- send to target list of player or all players
		if playerList then
			for _, LocalPlayer in ipairs( playerList ) do
				Bridge:FireClient( LocalPlayer, RemoteEnums.Set, category, data )
			end
		else
			Bridge:FireAllClients( RemoteEnums.Set, category, data )
		end
	end

	-- get the first occurance of data (whitelist = private, otherwise public)
	function Module.GetData( category : string, whitelistPlayer : Player? )
		-- public data
		if not whitelistPlayer then
			return Module.Replications[ category ]
		end
		-- private data
		for i, DataTable in ipairs(Module.Replications.Private) do
			local _, Cat, Dat, PlayerTable = unpack(DataTable)
			if Cat == category and table.find(PlayerTable, whitelistPlayer ) then
				return Dat, i
			end
		end
		return nil
	end

	-- set data in the category (public or private depending on whitelist)
	function Module.SetData( category : string, data : any, whitelist : { Player }? )
		if whitelist then
			-- private data for a select group of players
			table.insert(Module.Replications.Private, { HttpService:GenerateGUID(false), category, data, whitelist })
		else
			Module.Replications.Public[ category ] = data
		end
		SendDataToPlayers( category, data, whitelist )
	end

	-- remove all under the category
	function Module.RemoveAll( category : string )
		if Module.Replications.Public[ category ] then
			Bridge:FireAllClients( RemoteEnums.Remove, category )
			Module.Replications.Public[ category ] = nil
		end
		-- properly deletes everything
		local index = 1
		while index <= #Module.Replications.Private do
			local replicationInfo = Module.Replications.Private[index]
			if replicationInfo[2] == category then
				table.remove(Module.Replications.Private, index)
				for _, LocalPlayer in ipairs( replicationInfo[4] ) do
					Bridge:FireClient( LocalPlayer, RemoteEnums.Remove, category )
				end
			else
				index += 1
			end
		end
	end

	-- remove any private replicated data relating to the player
	function Module.RemoveDataForPlayer( category : string, LocalPlayer : Player )
		-- filter all private replications and remove any occurances of the player from the player tables
		-- in addition, if any of the player tables become empty, remove the replication data
		local index = 1
		while index <= #Module.Replications.Private do
			local replicationInfo = Module.Replications.Private[index]
			local playerIndex = table.find( replicationInfo[4], LocalPlayer )
			if replicationInfo[2] == category and playerIndex then
				Bridge:FireClient( LocalPlayer, RemoteEnums.Remove, category )
				table.remove( replicationInfo[4], playerIndex)
				if #replicationInfo[4] == 0 then -- empty player table, delete
					table.remove( Module.Replications.Private, index)
				end
			else
				index += 1
			end
		end
	end

	local function Update( TargetPlayer : Player? )
		for category, data in pairs( Module.Replications.Public ) do
			if TargetPlayer then
				SendDataToPlayers( category, data, { TargetPlayer } )
				continue
			end

			local hasUpdated = CheckComparisonUpdate( category, data, nil )
			-- print('public: ', category, hasUpdated)
			if not hasUpdated then
				continue
			end
			SendDataToPlayers( category, data, nil )
		end

		local index = 1
		while index <= #Module.Replications.Private do
			local replicationInfo = Module.Replications.Private[index]

			-- check if player table is empty
			local UUID, Category, Data, PlayerTable = unpack( replicationInfo )
			if #PlayerTable == 0 then
				table.remove( Module.Replications.Private, index )
				continue
			end

			-- if data has updated
			local hasUpdated = CheckComparisonUpdate( Category, Data, UUID )
			-- print('Private: ', Category, index, hasUpdated)
			if TargetPlayer then
				-- update specific player
				if table.find( PlayerTable, TargetPlayer ) then
					SendDataToPlayers( Category, Data, {TargetPlayer} )
				end
			elseif hasUpdated then
				-- update all players
				SendDataToPlayers( Category, Data, PlayerTable )
			end

			-- increment to next index
			index += 1
		end
	end

	function Module.Init(_)

		local Debounce = {}
		Bridge:OnServerEvent(function(LocalPlayer)
			if Debounce[LocalPlayer.Name] and time() < Debounce[LocalPlayer.Name] then
				return
			end
			Debounce[LocalPlayer.Name] = time() + 2

			-- print(LocalPlayer.Name, 'requested for update')
			Update( LocalPlayer )
		end)

		local function OnPlayerAdded( LocalPlayer )
			task.defer(Update, LocalPlayer )
			LocalPlayer.CharacterAdded:Connect(function()
				task.defer(Update, LocalPlayer )
			end)
		end

		for _ , LocalPlayer in ipairs(Players:GetPlayers()) do
			OnPlayerAdded(LocalPlayer)
		end
		Players.PlayerAdded:Connect(OnPlayerAdded)

		-- auto update players every n seconds
		task.defer(function()
			while true do
				task.wait(0.25)
				Update()
			end
		end)

	end

	function Module.Start()

	end

else

	Module.Replicated = { }

	function Module.GetData( category : string, yield : boolean? )
		while yield and not Module.Replicated[category] do
			task.wait(0.15)
		end
		return Module.Replicated[category]
	end

	function Module.Init(_)

		Bridge:OnClientEvent(function(Job, category, data)
			if Job == RemoteEnums.Set then
				local DoesExist = (Module.Replicated[category] ~= nil)
				if DoesExist then
					for propName, propValue in pairs( data ) do
						Module.Replicated[category][propName] = propValue
					end
				else
					Module.Replicated[category] = data
				end
				if not DoesExist then
					Module.OnAdded:Fire(category, data)
				end
				Module.OnUpdated:Fire(category, data)
			elseif Job == RemoteEnums.Remove then
				Module.Replicated[category] = nil
				Module.OnRemoved:Fire(category)
			end
		end)

	end

	function Module.Start()
		-- keep requesting until data is available
		while not Module.GetData('PlayerData') do
			print('requesting data from server')
			Bridge:FireServer()
			task.wait(2)
		end
	end

end

return Module
