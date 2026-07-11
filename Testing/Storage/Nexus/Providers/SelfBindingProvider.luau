local SelfBindingProvider = {
	Priority = -1000,
}

function SelfBindingProvider:Init()
	if self ~= SelfBindingProvider then error("Init was called without binding the provider as self") end

	if not self.BeforeInitSelfBound then error("BeforeInit did not receive the extension as self") end

	self.InitSelfBound = true
end

function SelfBindingProvider:Start()
	if self ~= SelfBindingProvider then error("Start was called without binding the provider as self") end

	if not self.BeforeStartSelfBound then error("BeforeStart did not receive the extension as self") end

	if not self.InitSelfBound then error("Init did not run with the provider instance") end
end

return SelfBindingProvider
