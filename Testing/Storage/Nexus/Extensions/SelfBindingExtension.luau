local SelfBindingExtension = {
	Name = "SelfBindingExtension",
	Prepared = false,
}

function SelfBindingExtension:Prepare()
	if self ~= SelfBindingExtension then error("Prepare was called without binding the extension as self") end

	self.Prepared = true
end

function SelfBindingExtension:BeforeInit(provider)
	if self ~= SelfBindingExtension then error("BeforeInit was called without binding the extension as self") end

	if provider.Name == "SelfBindingProvider" then provider.BeforeInitSelfBound = self.Prepared end
end

function SelfBindingExtension:BeforeStart(provider)
	if self ~= SelfBindingExtension then error("BeforeStart was called without binding the extension as self") end

	if provider.Name == "SelfBindingProvider" then provider.BeforeStartSelfBound = self.Prepared end
end

return SelfBindingExtension
