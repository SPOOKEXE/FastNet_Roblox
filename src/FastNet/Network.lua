local RunService = game:GetService('RunService')
local HttpService = game:GetService('HttpService')

local zlibModule = require(script.Parent.zlib)

local function ToHex( input : string ) : string
	return string.gsub(input, ".", function(c)
		return string.format("%02X", string.byte(c :: any))
	end)
end

local function FromHex( input : string ) : string
	return string.gsub( input, "..", function(cc)
		return string.char(tonumber(cc, 16) :: number)
	end)
end

local function DeepCopy(value : any) : any
	if typeof(value) == "table" then
		local clonedTable = {}
		for i,v in value do
			clonedTable[DeepCopy(i)] = DeepCopy(v)
		end
		return clonedTable
	end
	return value
end

--[[
	local function ConvertTableToCompressedValues( array )
		array = DeepCopy(array)

		local instanceToUUID = {}
		local uuidToInstance = {}
		local function getInstanceUUID( inst )
			if instanceToUUID[inst] then
				return instanceToUUID[inst]
			end
			local uuid = HttpService:GenerateGUID(false)
			uuidToInstance[ uuid ] = inst
			instanceToUUID[ inst ] = uuid
			return uuid
		end

		local visited = {}
		local function deepSearch( t )
			if visited[t] then
				return
			end
			visited[t] = true

			for propName, propValue in pairs(t) do
				-- index
				-- print('check index: ', propName)
				if typeof(propName) == "table" then
					deepSearch( propName )
				elseif typeof(propName) == "Instance" then
					local uuid = getInstanceUUID( propName )
					-- print(propName, uuid)
					t[uuid] = propValue
					t[propName] = nil
				end
				-- value
				-- print("check value; ", propValue)
				if typeof(propValue) == "table" then
					deepSearch( propValue )
				elseif typeof(propValue) == "Instance" then
					local uuid = getInstanceUUID( propValue )
					-- print(propValue, uuid)
					t[propName] = uuid
				end
			end

		end

		deepSearch( array )

		-- print(array, uuidToInstance)
		array = HttpService:JSONEncode(array)
		array = ToHex(array)
		array = zlibModule.Zlib.Compress(array)
		return array, uuidToInstance
	end

	local function ConvertCompressedValuesToTable( compressed, instanceCache )
		compressed = zlibModule.Zlib.Decompress(compressed)
		compressed = FromHex(compressed)
		local processed = HttpService:JSONDecode(compressed)

		-- print(compressed, instanceCache)

		local visited = { }

		local function deepSearch( t )
			if visited[t] then
				return
			end
			visited[t] = true

			for propName, propValue in pairs(t) do
				-- index
				if typeof(propName) == "table" then
					deepSearch( propName )
				elseif typeof(propName) == "string" then
					local inst = instanceCache[propName]
					if inst then
						t[propName] = nil
						t[inst] = propValue
					end
				end
				-- value
				if typeof(propValue) == "table" then
					deepSearch( propValue )
				elseif typeof(propValue) == "string" then
					local inst = instanceCache[propValue]
					if inst then
						t[propName] = inst
					end
				end
			end
		end

		deepSearch( processed )
		return processed
	end
]]

local Module = {}

if RunService:IsServer() then

	function Module.FireClient( remoteEvent : RemoteEvent, target : Player, ... : any? )
		remoteEvent:FireClient(target, ...) -- ConvertTableToCompressedValues(...)
	end

	function Module.FireAllClients( remoteEvent : RemoteEvent, ... : any? )
		remoteEvent:FireAllClients(...) -- ConvertTableToCompressedValues(...)
	end

	function Module.OnServerEvent( remoteEvent : RemoteEvent, callback : (...any?) -> any? )
		remoteEvent.OnServerEvent:Connect(function(playerInstance, ... : any?)
			--local decompressed = ConvertCompressedValuesToTable(...)
			--callback(playerInstance, unpack(decompressed))
			callback(playerInstance, ...)
		end)
	end

else

	function Module.FireServer( remoteEvent : RemoteEvent, ... : any? )
		remoteEvent:FireServer(...)-- ConvertTableToCompressedValues(...)
	end

	function Module.OnClientEvent( remoteEvent : RemoteEvent, callback : (...any?) -> any? )
		remoteEvent.OnClientEvent:Connect(function(... : any?)
			--local value = ConvertCompressedValuesToTable(...)
			--callback(unpack(value))
			callback(...)
		end)
	end

end

return Module
