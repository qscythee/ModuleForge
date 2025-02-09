----------------------------------------------------------------------------------------------------------

-- Authors: Matthew (@qscythee)
-- February 05, 2025
--[=[
	@class Nexus

	Nexus is a module loading provider framework forked from Roam that is inspired by Sleitnick's Axis
	framework: https://github.com/Sleitnick/Axis.) This module loader is very barebones and does not feature
	a built-in networking layer like Knit and doesn't utilize Axis's extension system.

	Nexus collects load-elligable modules (modules that pass the predicate if one is supplied) and
	initializes them "syncronously" in the order they were collected in - the order is determined
	"randomly" or by the table of paths provided by the developer. Once all modules are initialized,
	Nexus then "starts" the modules "asyncronously" by spawning the "Start" method in a new thread.

	[NOTES]
	* Nexus does not need to be required in each module.
	* All modules are guaranteed safe to access in the "Start" method.
	* All modules are guaranteed to be initialized before the "Start" method is
	spawned.
	* Modules do not have to have either the "Init" or "Start" method.
	* Modules are guaranteed to be initialized in the order they were defined if a
	custom load order is provided, otherwise it is "random".
	* The name "Module" or "Controller" is not required, you decide what convention
	to follow when naming your modules.

	[EXAMPLE USAGE]
	```lua
	local MyModule = {
		Config = {
			Name = "MyModule", -- Optional, name is auto-generated.
			Dependencies = {
				MyOtherModule,
			},
		},
	}

	function MyModule:Add(x: number, y: number): number
		return x + y
	end

	function MyModule:Init()
		print("MyModule initialized!")
		print("This is safe to do:", MyOtherModule:SomeMethod())
	end

	function MyModule:Start()
		print("MyModule started!")
		print(MyModule:Add(1, 2))
	end

	return MyModule
	```
]=]

----------------------------------------------------------------------------------------------------------

local RunService = game:GetService("RunService")

local Packages = script.Parent
local Promise = require(Packages.Promise) ---@module _Promise
local Signal = require(Packages.Signal) ---@module _Signal

local startedSignal = Signal.new()
local loadedModules: { [string]: Module } = {}
local isDebug = false

local CONTEXT = if RunService:IsServer() then "SERVER" else "CLIENT"

--[=[
	@within Nexus
	@interface StartConfig
	.LoadOrder {string}? -- A table of module paths that will be loaded in the order they are provided.
	.PostInitPreStartCallback (() -> Promise)? -- A callback that is called after all modules have been
	initialized but before they are started.
	.Debug boolean? -- Whether to log debug information.
]=]
export type StartConfig = {
	LoadOrder: {string}?,
	PostInitPreStartCallback: (() -> Promise?)?,
	Debug: boolean?,
}

--[=[
	@within Nexus
	@interface Module
	.Init (self: Module) -> ()? -- The method that is spawned syncronously when the module is initialized.
	.Start (self: Module) -> ()? -- The method that is spawned asyncronously when the module is started.
]=]
export type Module = {
	Name: string?,
	Dependencies: { Module }?,
	Init: <T>(self: T) -> ()?,
	Start: <T>(self: T) -> ()?,
	[any]: any,
}

export type DirectoryPredicate = (moduleScript: ModuleScript) -> boolean

type LoadedModule = Module & {
	Name: string,
	_IsInit: true,
	_IsStart: true,
}

type Promise = typeof(Promise.new())

type Directory = Folder | ModuleScript

----------------------------------------------------------------------------------------------------------

-- Checks if a module already exists.
local function doesModuleExists(name: string): boolean
	return loadedModules[name] ~= nil
end

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
			assert(success, `Failed to load module: {scr.Name}\n{msg}`)
		end)
		assert(coroutine.status(current) == "dead", "Require yielded: ".. scr:GetFullName())
	end)
	return mod
end

-- Logs a debug message.
local function log(level: "Log" | "Warn" | "Error", ...: any)
	if not isDebug then return end

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

----------------------------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------------------------

local Nexus = {
	Started = startedSignal,
	IsStarted = false,
	Modules = nil :: { [string]: Module }?,
	Predicates = {},
}

function Nexus.Predicates.MatchesName(name: string): (moduleScript: ModuleScript) -> boolean
	return function(moduleScript: ModuleScript): boolean
		return moduleScript.Name:match(name) ~= nil
	end
end

function Nexus.Predicates.IsModule(moduleScript: ModuleScript): boolean
	return moduleScript.Name:match("Module$") ~= nil
end

function Nexus.Predicates.IsController(moduleScript: ModuleScript): boolean
	return moduleScript.Name:match("Controller$") ~= nil
end

function Nexus.Predicates.IsProvider(moduleScript: ModuleScript): boolean
	return moduleScript.Name:match("Provider$") ~= nil
end

----------------------------------------------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------------------------------------------

--[=[
	Sets debug mode to the given value or flips the current value if no value is provided.
]=]
function Nexus.ToggleDebug(value: boolean?)
	isDebug = if value ~= nil then value else not isDebug
end

--[=[
	Returns a module by name. Will error if the module doesn't exist.

	:::caution Safety
	Modules are only safe to access after Nexus has started! If you try to access a module before Nexus
	has started, you could encounter unexpected behavior.
	:::

	```lua
	local MyModule = Nexus.GetModule("MyModule")
	-- Safe ONLY after Nexus has started.
	MyModule:SomeMethod()
	```
]=]
function Nexus.GetModule(name: string): Module
	if not Nexus.IsStarted then
		warn(debug.traceback("HEADS UP! Nexus hasn't started, modules ARE NOT safe to access yet!"))
	end
	assert(typeof(name) == "string", "Arg #1 'name' must be a string.")
	return assert(loadedModules[name], `Module with name '{name}' does not exist.`)
end

--[=[
	Returns the name of a module.

	```lua
	local MyModule = Nexus.GetModule("MyModule")
	print(Nexus.GetNameFromModule(MyModule)) -- "MyModule"
	```
]=]
function Nexus.GetNameFromModule(module: Module): string
	assert(typeof(module) == "table", "Arg #1 'module' must be a table.")
	assert(typeof(module.Name) == "string", "Module.Config.Name must be a string.")
	return module.Name
end

--[=[
	Recursively registers modules in the provided directories.

	@param dir Folder | ModuleScript | { Folder | ModuleScript } -- The directory or directories
	to search for modules.
	@param predicate (moduleScript: ModuleScript) -> boolean -- The predicate to filter modules.
	@param depth number? -- The depth to recursively search for modules. Defaults to math.huge.
]=]
function Nexus.RegisterModulesIn(
	dir: Directory | { Directory },
	predicate: DirectoryPredicate?,
	depth: number?
)
	if typeof(dir) == "Instance" then
		dir = { dir }
	end

	assert(not predicate or typeof(predicate) == "function", "Arg #2 'predicate' must be a function or nil.")

	depth = depth or math.huge
	assert(typeof(depth) == "number", "Arg #3 'depth' must be a number or nil.")

	local modules = {}

	local function search(inst: Instance | { Instance }, currentDepth: number)
		if currentDepth >= depth then return end

		if typeof(inst) == "table" then
			for _, child in pairs(inst) do
				search(child, currentDepth)
			end
			return
		end

		assert(typeof(inst) == "Instance", "Arg #1 'dir' must be an Instance or a table of Instances.")

		if inst:IsA("ModuleScript") then
			if not predicate or predicate(inst) then
				local mod = ensureUnyieldingRequire(inst)
				if typeof(mod) ~= "table" then
					warn(`Module at '{inst:GetFullName()}' is not a table, skipping.`)
					return
				end

				mod.Name = mod.Name or inst.Name

				Nexus.RegisterModule(mod)
				table.insert(modules, mod)
			end
		elseif inst:IsA("Folder") then
			search(inst:GetChildren(), currentDepth + 1)
		end
	end

	return modules
end

--[=[
	Registers a module to be loaded by Nexus. This method should be called before Nexus.Start is called.
]=]
function Nexus.RegisterModule(module: Module)
	if Nexus.IsStarted then
		warn(debug.traceback("Cannot register module after Nexus has started."))
		return
	end

	assert(typeof(module) == "table", "Arg #1 'module' must be a table.")

	local name = module.Name
	assert(typeof(name) == "string", "Module.Config.Name must be a string or nil.")

	if doesModuleExists(name) then
		error(`Module with name '{name}' already exists.`)
	end

	log("Log", `Module '{name}' registered -`, module)

	loadedModules[name] = module
end

-- Performs topological sorting of modules based on their dependencies.
local function topologicalSort(modules: { [string]: Module }): { Module }
	local sorted, visited, checking = {}, {}, {}

	local function visit(mod: Module, path: string?)
		if checking[mod] then error(`Cyclic dependency detected in path: {mod.Name} -> {path}`) end
		if visited[mod] then return end

		checking[mod] = true

		if typeof(mod.Dependencies) == "table" then
			for dep in mod.Dependencies do
				visit(dep, if path then path..` -> {dep.Name}` else `{dep.Name}`)
			end
		end

		checking[mod] = nil
		visited[mod] = true

		table.insert(sorted, mod)
	end

	for _, module in modules do visit(module) end

	return sorted
end

--[=[
	Starts Nexus by initializing and starting all registered modules.

	:::caution Call Once
	Can only be called once. Calling more than once will throw an error.
	You cannot register modules after Nexus has started.
	:::

	```lua
	Nexus.ToggleDebug(true)

	Nexus.Start({
		LoadOrder = {
			"MyOtherModule",
			"MyModule",
		},
		PostInitPreStartCallback = function()
			print("All modules have been initialized, about to start them!")
		end,
		Debug = true, -- Same as calling Nexus.ToggleDebug(true)
	}):andThen(function()
		print("Nexus has fully started!")
	end):catch(warn)
	```

	@param config StartConfig? -- The configuration for starting Nexus.
	@return Promise -- A promise that is resolved once Nexus has fully started.
]=]
function Nexus.Start(config: StartConfig?): Promise
	if Nexus.IsStarted then
		return Promise.reject("Nexus has already started.")
	end

	config = config or {}
	if typeof(config) ~= "table" then
		error(`Arg #1 'config' must be a table, got {typeof(config)}`)
	end

	if config.Debug ~= nil then
		Nexus.ToggleDebug(config.Debug)
	end

	if config.PostInitPreStartCallback and typeof(config.PostInitPreStartCallback) ~= "function" then
		error(`config.PostInitPreStartCallback must be a function or nil, got {typeof(config.PostInitPreStartCallback)}`)
	end

	if config.LoadOrder and typeof(config.LoadOrder) ~= "table" then
		error(`config.LoadOrder must be a table or nil, got {typeof(config.LoadOrder)}`)
	end

	local sortedModules: { Module }

	if config.LoadOrder then
		-- todo: implement custom load order
	else
			-- Sort modules topologically based on dependencies
		sortedModules = topologicalSort(loadedModules)
		log("Log", "No load order provided, modules were sorted topologically:", sortedModules)
	end

	return Promise.new(function(resolve)
		table.freeze(loadedModules)

		log("Log", "Modules to be init/started:", sortedModules)
		log("Log", "Starting Nexus...")

		-- Init:
		local totalInitTime = 0
		local proms = {}
		for _, mod in sortedModules do
			if typeof(mod.Init) ~= "function" then continue end

			local prom = Promise.new(function(r)
				local t = os.clock()
				local debugName = `{mod.Name}:Init`

				debug.setmemorycategory(debugName)
				debug.profilebegin(debugName)

				mod:Init()
				mod.Init = function()
					log("Error", `Cannot call 'Init' on {mod.Name}, it has already been initialized!`)
				end

				mod._IsInit = true

				t = os.clock() - t
				totalInitTime += t

				log("Log", `Module '{mod.Name}' initialized in {round(t, 6)}ms.`)
				return r()
			end)

			table.insert(proms, prom)
			prom:await()
		end

		Nexus.Modules = loadedModules

		resolve(Promise.all(proms):tap(function()
			log("Log", `ALL modules initialized in {round(totalInitTime, 6)}ms.`)
		end))
	end)
	:andThen(function()
		if config.PostInitPreStartCallback then
			return config.PostInitPreStartCallback() :: Promise?
		end
		return nil
	end)
	:andThen(function()
		-- Start:

		for _, mod in sortedModules do
			if typeof(mod.Start) ~= "function" then continue end

			task.spawn(function()
				local t = os.clock()
				local debugName = `{mod.Name}:Start`

				debug.setmemorycategory(debugName)
				debug.profilebegin(debugName)

				mod:Start()
				mod.Start = function()
					log("Error", `Cannot call 'Start' on {mod.Name}, it has already been started!`)
				end

				mod._IsStart = true

				t = os.clock() - t

				log("Log", `Module '{mod.Name}' started in {round(t, 6)}ms.`)
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
		local MyModule = Nexus.GetModule("MyModule")
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

----------------------------------------------------------------------------------------------------------
-- Private Methods
----------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------
-- End
----------------------------------------------------------------------------------------------------------

return Nexus
