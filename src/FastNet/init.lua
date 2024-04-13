
local Bridges = require(script.Bridges)

export type Packet = Bridges.Packet
export type BaseBridge = Bridges.BaseBridge
export type ServerBridge = Bridges.ServerBridge
export type ClientBridge = Bridges.ClientBridge

-- // Module // --
local Module = {}

function Module.Create( bridgeName : string, unreliable : boolean ) : ServerBridge | ClientBridge
	return Bridges.Create(bridgeName, unreliable)
end

return Module
