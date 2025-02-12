----------------------------------------------------------------------------------------------------------------------------------------

-- Authors: Matthew (@qscythee)
-- February 05, 2025
--[=[
	@class Nexus

	Nexus is a module loading provider framework forked from Roam that is inspired by Sleitnick's [Axis
	framework](https://github.com/Sleitnick/Axis).) This module loader is barebones with the exception
	of extensions. There is no built-in networking layer or built-in state management. Nexus is designed
	to be a simple, yet powerful module loader that allows developers to easily load and manage modules
	in their game with the ability to add extensions for additional functionality.

	Nexus collects load-elligable modules (modules that pass the predicate if one is supplied) and
	initializes them "syncronously" in the order they were collected in - the order is determined
	"randomly" or by the table of paths provided by the developer. Once all modules are initialized,
	Nexus then "starts" the modules "asyncronously" by spawning the "Start" method in a new thread.

	### NOTES
	* Nexus does not need to be required in each module.
	* All modules are guaranteed safe to access in the "Start" method.
	* All modules are guaranteed to be initialized before the "Start" method is
	spawned.
	* Providers do not have to have either the "Init" or "Start" method.
	* Providers are guaranteed to be initialized in the expected order VIA the custom
	load order or topological sorting where dependencies are actually respected.
	* The name "Provider", "Service", or "Controller" is not required, you decide
	what convention to follow when naming your modules.
	* Extensions are optional and are used to extend the functionality of modules
	under-the-hood. They are there to save time writing common boilerplate code.

	### EXAMPLE USAGE
	```lua
	local MyProvider = {
		Config = {
			Name = "MyProvider", -- Optional, name is auto-generated.
			Dependencies = {
				[MyOtherProvider] = true,
			},
		},
	}

	function MyProvider:Add(x: number, y: number): number
		return x + y
	end

	function MyProvider:Init()
		print("MyProvider initialized!")

		-- This is 100% safe to do:
		print("OtherProvider runtime data:", MyOtherProvider:SomeMethod())
	end

	function MyProvider:Start()
		print("MyProvider started!")
		print(MyProvider:Add(1, 2))
	end

	return MyProvider
	```
]=]

----------------------------------------------------------------------------------------------------------------------------------------

-- Roblox Services
local RunService = game:GetService("RunService")

-- Imports
local Packages = script.Parent
local Promise = require(Packages.Promise) ---@module _Promise
local Signal = require(Packages.Signal) ---@module _Signal

-- Vars
local startedSignal = Signal.new()
local loadedExtensions: { [string]: Extension } = {}
local loadedProviders: { [string]: Provider } = {}

-- Consts
local CONTEXT = if RunService:IsServer() then "SERVER" else "CLIENT"

--[=[
	@within Nexus
	@interface StartConfig
	.ExtensionsToLoad { ModuleScript }? -- A table of module scripts of extensions that will be registered
	and loaded in the order they are provided.
	.ProvidersToLoad { ModuleScript }? -- A table of module scripts of modules that will be registered and
	loaded in the order they are provided.
	.PostInitPreStartCallback (() -> Promise)? -- A callback that is called after all modules have been
	initialized and before they are started.
	.Debug boolean? -- Whether to log debug information.
]=]
export type StartConfig = {
	ExtensionsToLoad: { ModuleScript }?,
	ProvidersToLoad: { ModuleScript }?,
	PostInitPreStartCallback: (() -> Promise?)?,
	Debug: boolean?,
}

--[=[
	@within Nexus
	@interface Provider
	.Init (self: Provider) -> ()? -- The method that is spawned syncronously when the provider is initialized.
	.Start (self: Provider) -> ()? -- The method that is spawned asyncronously when the provider is started.
]=]
export type Provider = {
	Name: string?,
	Dependencies: { Provider }?,
	Init: <T>(self: T) -> ()?,
	Start: <T>(self: T) -> ()?,
	[any]: any,
}

export type DirectoryPredicate = (moduleScript: ModuleScript) -> boolean

--[=[
	@within Nexus
	@interface Extension
	.BeforeInit (self: Extension, provider: Provider) -> ()? -- The hook that fires before each provider is initialized.
	.BeforeStart (self: Extension, provider: Provider) -> ()? -- The hook that fires before each provider is started.

	Extensions allow developers to extend the functionality of modules under-the-hood.
	This is useful for adding additional functionality to modules without modifying the provider itself.
	Developers can save time writing common boilerplate code by using extensions, however, extensions
	do add a layer of abstraction. The use of extensions is optional and not required.
]=]
export type Extension = {
	BeforeInit: <T>(self: T, provider: Provider) -> ()?,
	BeforeStart: <T>(self: T, provider: Provider) -> ()?,
	[any]: any,
}

type LoadedProvider = Provider & {
	Name: string,
	_IsInit: true,
	_IsStart: true,
}

type Promise = typeof(Promise.new())
type Directory = Folder | ModuleScript

----------------------------------------------------------------------------------------------------------------------------------------
-- Provider
----------------------------------------------------------------------------------------------------------------------------------------

local Nexus = {
	Debug = false,
	Started = startedSignal,
	IsStarted = false,
	Providers = nil :: { [string]: Provider }?,
	Predicates = {},
}

-- requires a given modulescript and throws a safe error if it yields.
local function ensureUnyieldingRequire(scr: ModuleScript)
	local mod
	task.spawn(function()
		local current
		task.spawn(function()
			current = coroutine.running()
			local success, msg = pcall(function()
				mod = require(scr) :: any
			end)
			if not success then error(`Failed to load module: {scr.Name}\n{msg}`) end
		end)
		if coroutine.status(current) ~= "dead" then error(`Require yielded: {scr:GetFullName()}`) end
	end)
	return mod
end

-- Logs a debug message.
local function log(level: "Log" | "Warn" | "Error", ...: any)
	if not Nexus.Debug then return end

	if level == "Log" then
		print(`<| NEXUS DEBUG |> [{CONTEXT}] `, ...)
	elseif level == "Warn" then
		warn(`<| NEXUS DEBUG |> [{CONTEXT}] `, ...)
	elseif level == "Error" then
		error(`<| NEXUS DEBUG |> [{CONTEXT}] {table.concat({ ... }, " ")}`, 2)
	end
end

-- Rounds a number to a given precision.
local function round(n: number, p: number?): number
	local m = 10 ^ math.floor(p or 0)
	return math.floor(n * m + 0.5) / m
end

-- Runs all the extensions for each provider.
local function runExtensions(fnName: string, prov: Provider)
	local function Run(ext: Extension)
		if typeof(ext[fnName]) ~= "function" then return end
		ext[fnName](ext, prov)
		log("Log", `Ran extension {ext.Name}:{fnName} for {prov.Name}.`)
	end

	for _, ext in loadedExtensions do
		Run(ext)
	end

	if typeof(prov.Extensions) == "table" then
		for _, ext in prov.Extensions do
			Run(ext)
		end
	end
end

-- Registers modules/extensions in their respective directories.
local function registerIn(type: "Provider" | "Extension", dir: Directory | { Directory }, predicate: DirectoryPredicate?, deepSearch: boolean?)
	if typeof(dir) == "Instance" then dir = { dir } end

	if Nexus.IsStarted then error(debug.traceback("Cannot register modules after Nexus has started.")) end
	if predicate ~= nil and typeof(predicate) ~= "function" then error(`Arg #2 'predicate' must be a function, got: {typeof(predicate)}`) end

	deepSearch = if deepSearch ~= nil then deepSearch else false
	if typeof(deepSearch) ~= "boolean" then error(`Arg #3 'deepSearch' must be a boolean or nil, got: {typeof(deepSearch)}`) end

	local provs = {}
	local function search(inst)
		if typeof(inst) == "table" then
			for _, child in inst do
				search(child)
			end
			return
		end

		if typeof(inst) ~= "Instance" then
			warn(debug.traceback(`Arg #1 'dir' must be an Instance or a table of Instances, got: {typeof(inst)}`))
			return
		end

		if inst:IsA("ModuleScript") then
			if inst:GetAttribute("Disabled") == true then return end

			if not predicate or predicate(inst) then
				local mod = ensureUnyieldingRequire(inst)
				if typeof(mod) ~= "table" then
					warn(`Provider at '{inst:GetFullName()}' is not a table, got: {typeof(mod)}`)
					return
				end

				if type == "Provider" then
					mod.Name = mod.Name or inst.Name
					mod._IsInit = false
					mod._IsStart = false
					Nexus.RegisterProvider(mod)
				elseif type == "Extension" then
					mod.Name = mod.Name or inst.Name
					Nexus.RegisterExtension(mod)
				end

				table.insert(provs, mod)

				if deepSearch then
					search(inst:GetChildren())
				end
			end
		elseif inst:IsA("Folder") then
			search(inst:GetChildren())
		end
	end
	search(dir)
	return provs
end

----------------------------------------------------------------------------------------------------------------------------------------
-- Provider Loading Predicates
----------------------------------------------------------------------------------------------------------------------------------------

--[=[
	@within Nexus
	@function Predicates.MatchesName
	Returns a predicate that matches a module script's name.

	@param name string -- The name to match.
	@return (moduleScript: ModuleScript) -> boolean
]=]
function Nexus.Predicates.MatchesName(name: string): (moduleScript: ModuleScript) -> boolean
	return function(moduleScript: ModuleScript): boolean
		return moduleScript.Name:match(name) ~= nil
	end
end

--[=[
	@within Nexus
	@function Predicates.IsService
	Returns the matching result of a module script's name ending with "Service".

	@param moduleScript ModuleScript
	@return boolean
]=]
function Nexus.Predicates.IsService(moduleScript: ModuleScript): boolean
	return moduleScript.Name:match("Service$") ~= nil
end

--[=[
	@within Nexus
	@function Predicates.IsController
	Returns the matching result of a module script's name ending with "Controller".

	@param moduleScript ModuleScript
	@return boolean
]=]
function Nexus.Predicates.IsController(moduleScript: ModuleScript): boolean
	return moduleScript.Name:match("Controller$") ~= nil
end

--[=[
	@within Nexus
	@function Predicates.IsProvider
	Returns the matching result of a module script's name ending with "Provider".

	@param moduleScript ModuleScript
	@return boolean
]=]
function Nexus.Predicates.IsProvider(moduleScript: ModuleScript): boolean
	return moduleScript.Name:match("Provider$") ~= nil
end

--[=[
	@within Nexus
	@function Predicates.IsComponent
	Returns the matching conditions of a module script being a component.
	This checks if the type is a table, if it has a metatable, and if the
	__tostring cotains "Component" in the beginning of the string.

	:::caution Compatibility
	This predicate is only compatible with component libraries that mimic
	Sleitnick's Component library! If you are using a different component
	library, that doesn't happen to follow the same structure, you will
	need to write your own predicate.
	:::

	@param moduleScript ModuleScript
	@return boolean
]=]
function Nexus.Predicates.IsComponent(moduleScript: ModuleScript): boolean
	local mod = require(moduleScript)
	return typeof(mod) == "table" and getmetatable(mod) and tostring(mod):match("^Component")
end

----------------------------------------------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------------------------------------------

--[=[
	Returns a provider by name. Will error if the provider doesn't exist.

	:::warning Safety
	Providers are only safe to access after Nexus has started! If you try to access a provider before Nexus
	has started, you could encounter unexpected behavior.

	```lua
	local MyProvider = Nexus.GetProvider("MyModule")
	-- Safe ONLY after Nexus has started.
	MyModule:SomeMethod()
	```
	:::
]=]
function Nexus.GetProvider(name: string): Provider
	if not Nexus.IsStarted then warn(debug.traceback("HEADS UP! Nexus hasn't started, modules ARE NOT safe to access yet!")) end
	if typeof(name) ~= "string" then error(`Arg #1 'name' must be a string, got: {typeof(name)}`) end
	if not loadedProviders[name] then error(`Provider with name '{name}' does not exist.`) end
	return loadedProviders[name]
end

--[=[
	Returns the name of a provider.

	```lua
	local MyProvider = Nexus.GetProvider("MyModule")
	print(Nexus.GetNameFromProvider(MyModule)) -- "MyModule"
	```
]=]
function Nexus.GetNameFromProvider(prov: Provider): string
	if typeof(prov) ~= "table" then error(`Arg #1 'provider' must be a table, got: {typeof(prov)}`) end
	if typeof(prov.Name) ~= "string" then error(`Provider.Name must be a string, got: {typeof(prov.Name)}`) end
	return prov.Name
end

--[=[
	Recursively registers extensions in the provided directories.

	@param dir Folder | ModuleScript | { Folder | ModuleScript } -- The directory or directories
	to search for modules.
	@param predicate (moduleScript: ModuleScript) -> boolean -- The predicate to filter extensions.
	@param deepSearch boolean? -- Whether to search recursively within module scripts.

	```lua
	Nexus.RegisterExtensionsIn(ServerScriptService.Extensions, Nexus.Predicates.IsExtension)
	```
]=]
function Nexus.RegisterExtensionsIn(dir: Directory | { Directory }, predicate: DirectoryPredicate?, deepSearch: boolean?)
	return registerIn("Extension", dir, predicate, deepSearch)
end

--[=[
	Registers an extension to be loaded by Nexus. This method should be called before Nexus.Start is called.
]=]--
function Nexus.RegisterExtension(ext: Extension): Extension
	if Nexus.IsStarted then error("Cannot register extension after Nexus has started.") end

	local name = ext.Name
	if typeof(name) ~= "string" then error(`Extension.Name must be a string, got: {typeof(name)}`) end
	if loadedProviders[name] then error(`Provider with name '{name}' already exists.`) end

	loadedExtensions[ext.Name] = ext
	log("Log", `Extension '{ext.Name}' registered -`, ext)
	return ext
end

--[=[
	Recursively registers modules in the provided directories.

	@param dir Folder | ModuleScript | { Folder | ModuleScript } -- The directory or directories
	to search for modules.
	@param predicate (moduleScript: ModuleScript) -> boolean -- The predicate to filter modules.
	@param deepSearch boolean? -- Whether to search recursively within module scripts.

	```lua
	Nexus.RegisterProvidersIn(ServerScriptService.Services, Nexus.Predicates.IsService)
	Nexus.RegisterProvidersIn(ReplicatedStorage.Client.Controllers, Nexus.Predicates.IsController)
	```
]=]
function Nexus.RegisterProvidersIn(dir: Directory | { Directory }, predicate: DirectoryPredicate?, deepSearch: boolean?)
	return registerIn("Provider", dir, predicate, deepSearch)
end

--[=[
	Registers a provider to be loaded by Nexus. This method should be called before Nexus.Start is called.
]=]
function Nexus.RegisterProvider(prov: Provider)
	if Nexus.IsStarted then
		warn(debug.traceback("Cannot register provider after Nexus has started."))
		return
	end

	if typeof(prov) ~= "table" then error(`Arg #1 'provider' must be a table, got: {typeof(prov)}`) end

	local name = prov.Name
	if typeof(name) ~= "string" then error(`Provider.Name must be a string, got: {typeof(name)}`) end
	if loadedProviders[name] then error(`Provider '{name}' already exists.`) end

	log("Log", `Provider '{name}' registered -`, prov)
	loadedProviders[name] = prov
end

-- Performs topological sorting of modules based on their dependencies.
local function topologicalSort(provs: { [string]: Provider }): { Provider }
	local sorted, visited, checking = {}, {}, {}

	local function visit(mod: Provider, path: string?)
		if checking[mod] then error(`Cyclic dependency detected in path: {mod.Name} -> {path}`) end
		if visited[mod] then return end

		checking[mod] = true

		if typeof(mod.Dependencies) == "table" then
			for dep in mod.Dependencies do
				visit(dep, if path then path .. ` -> {dep.Name}` else `{dep.Name}`)
			end
		end

		checking[mod] = nil
		visited[mod] = true

		table.insert(sorted, mod)
	end

	for _, prov in provs do
		visit(prov)
	end

	return sorted
end

--[=[
	Starts Nexus by initializing and starting all registered modules.

	:::warning Call Once
	Can only be called once. Calling more than once will throw an error.
	You cannot register modules after Nexus has started.

	```lua
	Nexus.ToggleDebug(true)

	Nexus.Start({
		ExtensionsToLoad = {
			ReplicatedStorage.Shared.Extensions.PlayerLifecycles,
		},
		ProvidersToLoad = {
			ReplicatedStorage.Shared.Providers.MySharedProvider,
			ServerScriptService.Server.Providers.MyServerProvider,
		},
		PostInitPreStartCallback = function()
			print("All modules have been initialized, about to start them!")
		end,
		Debug = true, -- Same as calling Nexus.ToggleDebug(true)
	}):andThen(function()
		print("Nexus has fully started!")
	end):catch(warn)
	```
	:::

	@param config StartConfig? -- The configuration for starting Nexus.
	@return Promise -- A promise that is resolved once Nexus has fully started.
]=]
function Nexus.Start(config: StartConfig?): Promise
	if Nexus.IsStarted then return Promise.reject("Nexus has already started.") end

	config = config or {}
	if typeof(config) ~= "table" then error(`Arg #1 'config' must be a table, got {typeof(config)}`) end

	if config.Debug ~= nil then Nexus.Debug = config.Debug end

	if config.PostInitPreStartCallback and typeof(config.PostInitPreStartCallback) ~= "function" then
		error(`config.PostInitPreStartCallback must be a function or nil, got {typeof(config.PostInitPreStartCallback)}`)
	end

	if config.ExtensionsToLoad and typeof(config.ExtensionsToLoad) ~= "table" then
		error(`config.ExtensionsToLoad must be a table or nil, got {typeof(config.ExtensionsToLoad)}`)
	end

	if config.ProvidersToLoad and typeof(config.ProvidersToLoad) ~= "table" then
		error(`config.ProvidersToLoad must be a table or nil, got {typeof(config.ProvidersToLoad)}`)
	end

	-- Load extensions in the order provided
	if config.ExtensionsToLoad then
		for i, module in config.ExtensionsToLoad do
			if typeof(module) ~= "table" and (typeof(module) ~= "Instance" or not module:IsA("ModuleScript")) then
				local typeSig = if typeof(module) == "Instance" then module.ClassName else typeof(module)
				warn(debug.traceback(`Extension at index {i} in config.ExtensionsToLoad is not a ModuleScript, got: {typeSig}`))
				continue
			end

			if typeof(module) == "table" then
				if not module.Name then
					warn(debug.traceback(`Entry at index {i} in config.ExtensionsToLoad is missing a 'Name' field.`))
					continue
				end
				if not loadedProviders[module.Name] then Nexus.RegisterExtension(module.Name) end
			end

			local ext = require(module :: any) :: Extension
			if typeof(ext) ~= "table" then
				warn(debug.traceback(`Extension at index {i} in config.ExtensionsToLoad ('{module:GetFullName()}') is not a table, got: {typeof(ext)}`))
				continue
			end

			local name = ext.Name or module.Name
			if not loadedExtensions[name] then
				ext.Name = name
				Nexus.RegisterExtension(ext)
			end
		end
		log("Log", "Custom load array, extensions were loaded in the order provided:", loadedExtensions)
	end

	local sortedModules: { Provider }
	if config.ProvidersToLoad then
		-- Load modules in the order provided
		sortedModules = {}
		for i, prov in config.ProvidersToLoad do
			if typeof(prov) ~= "table" and (typeof(prov) ~= "Instance" or not prov:IsA("ModuleScript")) then
				local typeSig = if typeof(prov) == "Instance" then prov.ClassName else typeof(prov)
				warn(debug.traceback(`Entry at index {i} in config.ProvidersToLoad is not a ModuleScript, got: {typeSig}`))
				continue
			end

			if typeof(prov) == "table" then
				if not prov.Name then
					warn(debug.traceback(`Provider at index {i} in config.ProvidersToLoad is missing a 'Name' field.`))
					continue
				end
				if not loadedProviders[prov.Name] then Nexus.RegisterProvider(prov.Name) end
				table.insert(sortedModules, prov)
			end

			local mod = require(prov :: any) :: Provider
			if typeof(mod) ~= "table" then
				warn(debug.traceback(`Provider at index {i} in config.ProvidersToLoad ('{prov:GetFullName()}') is not a table, got: {typeof(mod)}`))
				continue
			end

			local name = mod.Name or prov.Name
			if not loadedProviders[name] then
				mod.Name = name
				Nexus.RegisterProvider(mod)
			end

			table.insert(sortedModules, mod)
		end
		log("Log", "Custom load array, modules were sorted by load order:", sortedModules)
	else
		-- Sort modules topologically based on dependencies
		sortedModules = topologicalSort(loadedProviders)
		log("Log", "Custom load array provided, modules were sorted topologically:", sortedModules)
	end

	return Promise.new(function(resolve)
		table.freeze(loadedProviders)

		log("Log", "Providers to be init/started:", sortedModules)
		log("Log", "Starting Nexus...")

		-- Init:
		local totalInitTime = 0
		local proms = {}
		for _, mod in sortedModules do
			if typeof(mod.Init) ~= "function" then continue end

			local prom = Promise.new(function(r)
				runExtensions("BeforeInit", mod)

				local t = os.clock()
				local debugName = `{mod.Name}:Init`

				debug.setmemorycategory(debugName)
				debug.profilebegin(debugName)

				mod:Init()
				mod.Init = function()
					error(`Cannot call 'Init' on {mod.Name}, it has already been initialized!`)
				end

				mod._IsInit = true

				t = os.clock() - t
				totalInitTime += t

				log("Log", `Provider '{mod.Name}' initialized in {round(t, 6)}ms.`)
				return r()
			end)

			table.insert(proms, prom)
			prom:await()
		end

		Nexus.Providers = loadedProviders

		resolve(Promise.all(proms):tap(function()
			log("Log", `ALL modules initialized in {round(totalInitTime, 6)}ms.`)
		end))
	end)
		:andThen(function()
			if config.PostInitPreStartCallback then return config.PostInitPreStartCallback() :: Promise? end
			return nil
		end)
		:andThen(function()
			-- Start:
			for _, mod in sortedModules do
				if typeof(mod.Start) ~= "function" then continue end

				runExtensions("BeforeStart", mod)

				task.spawn(function()
					local t = os.clock()
					local debugName = `{mod.Name}:Start`

					debug.setmemorycategory(debugName)
					debug.profilebegin(debugName)

					mod:Start()
					mod.Start = function()
						error(`Cannot call 'Start' on {mod.Name}, it has already been started!`)
					end

					mod._IsStart = true

					t = os.clock() - t

					log("Log", `Provider '{mod.Name}' started in {round(t, 6)}ms.`)
				end)
			end

			Nexus.IsStarted = true
			startedSignal:Fire()

			log("Log", "Nexus has STARTED SUCCESSFULLY!")
		end)
end

--[=[
	@return Promise
	Returns a promise that is resolved once Nexus has fully started. This is useful for any code that
	needs to tie into Nexus modules but is not the script that called `Start`.

	```lua
	Nexus.PromiseOnStarted():andThen(function()
		local MyProvider = Nexus.GetProvider("MyModule")
		MyModule:SomeMethod()
	end):catch(warn)
	```
]=]
function Nexus.PromiseOnStarted()
	if Nexus.IsStarted then
		return Promise.resolve()
	else
		return Promise.fromEvent(Nexus.Started)
	end
end

function Nexus.GetIsStarted()
	return Nexus.IsStarted
end

----------------------------------------------------------------------------------------------------------------------------------------
-- End
----------------------------------------------------------------------------------------------------------------------------------------

return Nexus
