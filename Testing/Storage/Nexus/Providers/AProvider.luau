local AProvider = {}

function AProvider:ExtensionBeforeInit(msg: string)
	print("AProvider ExtensionABeforeInit: " .. msg)
end

function AProvider:ExtensionBeforeStart(msg: string)
	print("AProvider ExtensionABeforeStart: " .. msg)
end

function AProvider:Start()
	print("AProvider Start")
end

function AProvider:Init()
	print("AProvider Init")
	AProvider.Foo = "Bar!"
end

return AProvider
