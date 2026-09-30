--[[
	Registry
	Holds every server service by name. Services reference each other through the registry
	at call time (never at require time) so there are no circular requires.
]]

local Registry = {} :: { [string]: any }

return Registry
