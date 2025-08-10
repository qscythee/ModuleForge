local AProviderScript = (script.Parent :: Folder):FindFirstChild("AProvider") :: ModuleScript
local AProvider = require(AProviderScript)

local CProvider = {
	Priority = 2000,

	Dependencies = {
		[AProvider] = true,
	},
}

function CProvider.Start()
	print("CProvider Start")
end

function CProvider.Init()
	print("CProvider Init")
	print("CProvider - AProvider foo: ", AProvider.Foo)
end

return CProvider
