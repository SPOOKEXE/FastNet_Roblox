local RunService = game:GetService('RunService')

local Threader = require(script.Parent.Threader) :: ((...any?) -> nil)
local Networker = require(script.Parent.Network)

local IS_SERVER = RunService:IsServer()

-- // Networker // --
local COMMAND_TYPES = { Fire = 1 }
local DEFAULT_PACKET_LIFETIME = 5 -- how long do packets stay in queue before being deleted
local PACKETS_PER_HEARTBEAT = 5
local ACTIVE_BRIDGES = {}

-- // Bridge Utilities // --

-- // Client Bridge // --
local ClientBridge = { ClassName = "ClientBridge" }
ClientBridge.__index = ClientBridge

function ClientBridge.Create(bridgeName)
	local bridgeEvent, bridgeFunction = CreateRemotePair( bridgeName )
	local self = setmetatable({
		_id = bridgeName,
		_queue = { },

		_eventHandlers = { }, -- when bridge is Fired
		_invokeHandlers = { returnFalse }, -- when bridge is Invoked
		_priorityNumbers = { },

		_event = bridgeEvent,
		_function = bridgeFunction,
	}, ClientBridge)

	Networker.ReceiveEvent(self._event, function(LocalPlayer : Player, ... : any?)
		for _, priorityNumber in ipairs( bridge._priorityNumbers ) do
			if not bridge._eventHandlers[priorityNumber] then
				continue
			end
			for _, callback in ipairs( bridge._eventHandlers[priorityNumber] ) do
				Threader(callback, LocalPlayer, ...)
			end
		end
	end)

	table.insert(ACTIVE_BRIDGES, self)
	return self
end

function ClientBridge:FireServer( ... : any? )
	table.insert(self._queue, {
		Type=COMMAND_TYPES.Fire,
		Args={...},
		TimeoutTick=tick() + DEFAULT_PACKET_LIFETIME,
	})
end

function ClientBridge:OnClientEvent(callback : (...any?) -> nil, priority : number?)
	return BRIDGE_EVENT_CALLBACK_PASS( self, callback, priority )
end

-- // Server Bridge // --
local ServerBridge = { ClassName = "ServerBridge" }
ServerBridge.__index = ServerBridge

function ServerBridge.Create(bridgeName)
	local bridgeEvent, bridgeFunction = CreateRemotePair( bridgeName )
	local self = setmetatable({
		_id = bridgeName,
		_queue = { },

		_eventHandlers = { }, -- when bridge is Fired
		_invokeHandlers = { returnFalse }, -- when bridge is Invoked
		_priorityNumbers = { },

		_event = bridgeEvent,
		_function = bridgeFunction,
	}, ServerBridge)

	Networker:ReceiveEvent(self._event, function(LocalPlayer : Player, ... : any?)
		for _, priorityNumber in ipairs( bridge._priorityNumbers ) do
			if not bridge._eventHandlers[priorityNumber] then
				continue
			end
			for _, callback in ipairs( bridge._eventHandlers[priorityNumber] ) do
				Threader(callback, LocalPlayer, ...)
			end
		end
	end)

	table.insert(ACTIVE_BRIDGES, self)
	return self
end

function ServerBridge:FireClient( LocalPlayer : Player, ... : any? )
	table.insert(self._queue, {
		Target=LocalPlayer,
		Type=COMMAND_TYPES.Fire,
		Args={...},
		TimeoutTick=tick() + DEFAULT_PACKET_LIFETIME,
	})
end

function ServerBridge:FireAllClients(... : any?)
	table.insert(self._queue, {
		Type=COMMAND_TYPES.Fire,
		Args={...},
		TimeoutTick=tick() + DEFAULT_PACKET_LIFETIME,
	})
end

function ServerBridge:OnServerEvent(callback : (...any?) -> any?, priority : number?)
	return BRIDGE_EVENT_CALLBACK_PASS( self, callback, priority )
end

-- // Module // --
local Module = {}

return Module
