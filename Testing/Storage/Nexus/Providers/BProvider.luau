local AProvider = require(script.Parent.AProvider)

local BProvider = {
	Dependencies = {
		[AProvider] = true,
	}
}

function BProvider:ExtensionBeforeInit(msg: string)
	print("BProvider ExtensionABeforeInit: " .. msg)
end

function BProvider:ExtensionBeforeStart(msg: string)
	print("BProvider ExtensionABeforeStart: " .. msg)
end

function BProvider:Start()
	print("BProvider Start")
end

function BProvider:Init()
	print("BProvider Init")
	print("BProvider - AProvider foo: ", AProvider.Foo)
end

return BProvider
