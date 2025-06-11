local ExtensionA = {}

function ExtensionA.BeforeInit(provider)
	if provider.ExtensionBeforeInit then provider:ExtensionBeforeInit("Hello, init!") end
end

function ExtensionA.BeforeStart(provider)
	if provider.ExtensionBeforeStart then provider:ExtensionBeforeStart("Hello, start!") end
end

function ExtensionA.Prepare()
	warn("Prepare!")
end

return ExtensionA
