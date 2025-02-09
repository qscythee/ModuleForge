-- Authors: Matthew (@qscythee)
-- February 08, 2025

type table = { [any]: any }

return function()
	local Nexus = require(script.Parent) ---@module Nexus
	--Nexus.ToggleDebug(true)

	local moduleCount = 0
	local function MakeTestModule(config: table?)
		config = config or {}
		assert(config, "Config is nil")
		moduleCount += 1
		config.Name = config.Name or `Module{moduleCount}`

		local module = {}
		module.Name = config.Name
		module.Dependencies = config.Dependencies or {}
		module._IsInit = false
		module._IsStart = false

		function module:Init()
			print("Init", self.Name)
		end

		function module:Start()
			print("Start", self.Name)
		end

		Nexus.RegisterModule(module)

		return module
	end

	print("Running test...")

	describe(".Start", function()
		local modA, modB, modC
		it("should register the module", function()
			modA = MakeTestModule({
				Name = "ModuleA",
				Dependencies = {},
			})

			modB = MakeTestModule({
				Name = "ModuleB",
				Dependencies = {},
			})

			modC = MakeTestModule({
				Name = "ModuleC",
				Dependencies = {},
			})

			modA.Dependencies[modB] = true
			modB.Dependencies[modC] = true
		end)

		it("should start modules in the proper order", function()
			local success = Nexus.Start():await()
			expect(success).to.be.ok()
		end)
	end)
end
