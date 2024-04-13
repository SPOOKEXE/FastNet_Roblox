local RunService = game:GetService("RunService")

local Networker = require(script.Parent.Network)

local ENABLE_ZLIB_COMPRESSION = true
local ENABLE_REMOTE_QUEUE = true
local PACKETS_PER_QUEUE_STEP = 10
local QUEUE_DEFAULT_TIMEOUT = 5

export type Packet = {
	args : {any},
	timeout : number,
	target : Player,
}

export type BaseBridge = {
	_id : string,
	_queue : { Packet },
	_middleware : { (BaseBridge, any) -> any },
	_eventcallbacks : { (...any?) -> nil },
	_priorityNumbers : { number },
	_event : RemoteEvent | UnreliableRemoteEvent,
}

export type ServerBridge = BaseBridge & {
	FireClient : (...any?) -> nil,
	FireAllClients : (...any?) -> nil,
	OnServerEvent : ((...any?) -> nil, number?) -> nil,
}

export type ClientBridge = BaseBridge & {
	FireServer : (...any?) -> nil,
	OnClientEvent : ((...any?) -> nil, number?) -> nil,
}

local ACTIVE_BRIDGES = {}
local BridgeCache = { }

local function CreateRemote( bridgeName : string, unreliable : boolean ) : RemoteEvent
	local Event = script:FindFirstChild(bridgeName..'_Event')
	if Event then
		return Event
	end
	if RunService:IsServer() then
		-- if server, create remotes that are missing
		if not Event then
			local className = unreliable and 'UnreliableRemoteEvent' or 'RemoteEvent'
			Event = Instance.new(className)
			Event.Name = bridgeName..'_'..className
			Event.Parent = script
		end
		return Event
	end
	return script:WaitForChild(bridgeName..'_Event')
end

local function SortBridgeNumbers( bridge )
	table.sort(bridge._priorityNumbers, function(a, b)
		return a > b
	end)
end

local function BRIDGE_EVENT_CALLBACK_PASS( bridge : BaseBridge, callback : (...any?) -> any?, priority : number? )
	priority = priority or 0
	if not table.find(bridge._priorityNumbers, priority) then
		table.insert(bridge._priorityNumbers, priority)
		SortBridgeNumbers( bridge )
	end

	if not bridge._eventHandlers[priority] then
		bridge._eventHandlers[priority] = { }
	end

	local priorityDict = bridge._eventHandlers[priority]
	local existantIndex = table.find( priorityDict, callback )
	if existantIndex then
		table.remove(priorityDict, existantIndex)
	end

	table.insert(priorityDict, 1, callback)
end

-- // Classes // --
local BaseBridge = {}
BaseBridge.__index = BaseBridge
BaseBridge.super = false

function BaseBridge.Create(name : string, unreliable : boolean) : BaseBridge
	local self = {
		_id = name,
		_queue = {},

		_middleware = {},
		_eventcallbacks = {},
		_priorityNumbers = {},

		_event = CreateRemote( name, unreliable ),
	}

	setmetatable(self, BaseBridge)

	return self
end

local ServerBridge = setmetatable({}, BaseBridge)
ServerBridge.__index = ServerBridge
ServerBridge.super = BaseBridge

function ServerBridge.Create(name : string, unreliable : boolean) : ServerBridge
	local self = BaseBridge.Create(name, unreliable)

	setmetatable(self, ServerBridge)

	return self
end

local ClientBridge = setmetatable({}, BaseBridge)
ClientBridge.__index = ClientBridge
ClientBridge.super = BaseBridge

function ClientBridge.Create(name : string, unreliable : boolean) : ClientBridge
	local self = BaseBridge.Create(name, unreliable)

	setmetatable(self, ClientBridge)

	return self
end

-- // Module // --
local Module = {}

function Module.Create( bridgeName : string, unreliable : boolean ) : ServerBridge | ClientBridge
	if BridgeCache[bridgeName] then
		return BridgeCache[bridgeName]
	end
	local Bridge = nil
	if RunService:IsServer() then
		Bridge = ServerBridge.Create(bridgeName, unreliable)
	else
		Bridge = ClientBridge.Create(bridgeName, unreliable)
	end
	BridgeCache[bridgeName] = Bridge
	return Bridge
end

local function UpdateBridgeTraffic(bridge : BaseBridge)
	local packet = table.remove(bridge._queue, 1)

	if RunService:IsServer() then -- server-side
		if packet.Target then
			Networker.FireClient( bridge._event, packet.Target, packet.Args )
		else
			Networker.FireAllClients( bridge._event, packet.Args )
		end
	else -- client-side
		if packet.Target then
			error("Invalid packet - cannot specify a target.")
		end
		Networker.FireServer( bridge._event, packet.Args )
	end
end

RunService.Heartbeat:Connect(function(_)
	local now = time()
	for _, bridge in ACTIVE_BRIDGES do
		-- clear dropped packets
		local index = 1
		while index <= #bridge._queue do
			local packet : Packet = bridge._queue[ index ]
			if now > packet.timeout then
				table.remove(bridge._queue, index) -- drop packets
			else
				index += 1
			end
		end
		-- update traffic
		if #bridge._queue == 0 then
			continue
		end
		for _ = 1, math.min( #bridge._queue, PACKETS_PER_QUEUE_STEP ) do
			UpdateBridgeTraffic( bridge )
		end
	end
end)

return Module
