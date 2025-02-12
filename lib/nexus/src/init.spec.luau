--!nocheck

-- Authors: Matthew (@qscythee)
-- February 08, 2025

local ReplicatedStorage = game:GetService("ReplicatedStorage")

type table = { [any]: any }

local TEST_CUSTOM_LOAD_ARRAY = true

return function()
	local Nexus = require(script.Parent) ---@module Nexus
	Nexus.Debug = true

	if TEST_CUSTOM_LOAD_ARRAY then
		describe("Start Nexus", function()
			it("should start modules in the proper order", function()
				local success = Nexus.Start({
					ExtensionsToLoad = {
						ReplicatedStorage.Storage.Nexus.Extensions.AExtension,
					},
					ProvidersToLoad = {
						ReplicatedStorage.Storage.Nexus.Providers.AProvider,
						ReplicatedStorage.Storage.Nexus.Providers.BProvider,
					},
				}):await()
				expect(success).to.be.ok()
			end)
		end)
	else
		describe("Register Extensions & Modules In Storage", function()
			it("should register extensions", function()
				local modules = Nexus.RegisterExtensionsIn(ReplicatedStorage.Storage.Nexus.Extensions)
				expect(modules).to.be.a("table")
				expect(modules).to.never.equal({})
			end)

			it("should register providers", function()
				local modules = Nexus.RegisterProvidersIn(ReplicatedStorage.Storage.Nexus.Providers, Nexus.Predicates.IsProvider)
				expect(modules).to.be.a("table")
				expect(modules).to.never.equal({})
			end)
		end)

		describe("Start Nexus", function()
			it("should start modules in the proper order", function()
				local success = Nexus.Start():await()
				expect(success).to.be.ok()
			end)
		end)
	end
end
