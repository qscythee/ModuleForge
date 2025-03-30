----------------------------------------------------------------------------------------------------------------------------------------

-- Authors: Matthew (@qscythee)
-- March 04, 2025
--[=[
	@class FlagManager

	FlagManager is a service-esque module that manages static/dynamic fast flags for your game.
	It allows you to create, modify, and delete flags at runtime with the ability to hot reload
	them across all servers. Flags are used to store static/dynamic state of any kind/structure.

	:::info STATIC VS DYNAMIC
	All flags are static by default and are assumed to be unserializable. Flags can store any type of
	data, however, in order to qualify as a dynamic fast flag, the data must be serializable.


	The following types are supported for serialization:
	---

	`boolean` | `number` | `string` | `table` | `Enum` | `Color3` | `ColorSequence` | `ColorSequenceKeypoint` |
	`NumberRange` | `NumberSequence` | `NumberSequenceKeypoint` | `UDim` | `UDim2` | `Vector2` | `Vector3` |
	`CFrame` | `Rect`
	:::

	### FLAGS
	* #### DYNAMIC
		* Sserialized and saved to the `Flags` datastore.
		* Serialization and deserialization are handled by the service before/after access.
		* Saved to the datastore when modified.
		* Deserialized from the datastore shortly after `:Start()` is called.
	* #### STATIC
		* Can be of any type.
		* Doesn't need to be serializable.
		* Can be modified at runtime.
		* Are not saved to the datastore.
		* Great for local debugging and testing.

	### SERIALIZATION
	* FlagManager uses a custom serializer (also available in ModuleForge) to serialize/deserialize
	dynamic flags.
	* The serializer is capable of serializing/deserializing any type of data that is native
	to Roblox and has APIs for custom data types.

	### NOTES
	* All flags are static by default.
	* Static flags are great for local debugging and testing.
	* Dynamic flags are great for storing dynamic state or "switches" that can be toggled at runtime,
	updating across all servers once the change is polled, no need to shutdown/migrate servers.
	* All flags are ready to be accessed after `:Start()` is called.


	### EXAMPLE USAGE
	```lua

	```
]=]

----------------------------------------------------------------------------------------------------------------------------------------

-- Imports
local Serializer = require(script.Serializer) ---@module Serializer
local TableManager = require(script.Parent.TableManager) ---@module _TableManager

-- Vars
local manager = TableManager.new()
local schema = {}

-- Types

--[=[
	@within FlagManager
	@interface Flag
	.Name string -- Name of the flag.
	.Value T -- Value of the flag.
	.IsDynamic boolean -- Whether the flag is dynamic or not.
	Use this type externally to type your flags.
]=]
export type Flag<T> = {
	Name: string,
	Value: T,
	IsDynamic: boolean,
}

--[=[
	@within FlagManager
	@interface StaticFlag
	.Name string -- Name of the flag.
	.Value any -- Value of the flag.
	.IsDynamic false -- Always static.
	Represents a registered static flag.
]=]
export type StaticFlag = {
	Name: string,
	Value: any,
	IsDynamic: false,
}

--[=[
	@within FlagManager
	@interface DynamicFlag
	.Name string -- Name of the flag.
	.Value Serializable -- Value of the flag.
	.IsDynamic true -- Always dynamic.
	Represents a registered dynamic flag.
]=]
export type DynamicFlag = {
	Name: string,
	Value: Serializable,
	IsDynamic: true,
}

--[=[
	@within FlagManager
	@interface SerializedFlag
	.Name string -- Name of the flag.
	.Value Serialized -- Serialized value of the flag.
	Represents a serialized dynamic flag.
]=]
export type SerializedFlag = {
	Name: string,
	Value: Serialized,
}

--[=[
	@within FlagManager
	@interface FlagStruct<T>
	.Name string -- Name of the flag. Can be multiple types as an array.
	.Type string | { string } -- Type of the flag.
	.IsDynamic boolean -- Whether the flag is dynamic or not.
	.Value T -- Value of the flag.
	Represents a flag schema structure.
]=]
export type FlagStruct<T> = {
	Name: string,
	Type: string | { string },
	IsDynamic: boolean,
	Value: T,
}

--- @within FlagManager
--- @type FlagSchema { [string]: FlagStruct<any> }
--- The schema of all your flags.
export type FlagSchema = {
	[string]: FlagStruct<any>,
}

type Serializable = Serializer.Serializable
type SerializableType = Serializer.SerializableType
type Serialized = Serializer.Serialized

----------------------------------------------------------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------------------------------------------------------

local FlagManager = {
	Flags = manager,
}

----------------------------------------------------------------------------------------------------------------------------------------
-- Private Methods
----------------------------------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------------------------------
-- Public Methods
----------------------------------------------------------------------------------------------------------------------------------------

--[=[
	@within FlagManager
	@method ObserveFlag
	Observes a flag for changes and calls the callback function when the flag is modified and when called.

	@param name string -- The name of the flag to observe.
	@param callback function -- The function to call when the flag is modified/first time running.
	@param runOnNil boolean? -- Whether to run the callback when the flag is nil. Defaults to true.

	@return Connection -- The connection object to disconnect the observation.
]=]
function FlagsManager:ObserveFlag(name: string, callback: (value: any) -> (), runOnNil: boolean?)
	assert(typeof(name) == "string", "Flag name must be of type string.")
	assert(typeof(callback) == "function", "Callback must be of type function.")

	runOnNil = if runOnNil ~= nil then runOnNil else true

	local flag = schema[name]
	if not flag then error(`Flag '{name}' does not exist.`) end

	return manager:Observe(name .. ".Value", function(value)
		callback(if flag.isDynamic then Serializer.Deserialize(value) else value)
	end, runOnNil)
end

--[=[
	@within FlagManager
	@method GetFlag
	Returns the value of a flag. Returns the deserialized value if the flag is dynamic.

	@param name string -- The name of the flag to get.

	@return any -- The value of the flag.
]=]
function FlagsManager:GetFlag(name: string): any
	assert(typeof(name) == "string", "Flag name must be of type string.")

	local flag = schema[name]
	if not flag then error(`Flag '{name}' does not exist.`) end

	local value = manager:Get(name .. ".Value")
	return if flag.isDynamic then Serializer.Deserialize(value) else value
end

--[=[
	@within FlagManager
	@method SetFlag

	Sets the value of a flag. Serializes the value if the flag is dynamic.

	@param name string -- The name of the flag to set.
	@param value any -- The value to set the flag to.
]=]
function FlagsManager:SetFlag(name: string, value: any)
	assert(typeof(name) == "string", "Flag name must be of type string.")

	local flag = schema[name]
	if not flag then error(`Flag '{name}' does not exist.`) end

	manager:Set(name .. ".Value", if flag.isDynamic then Serializer.Serialize(value) else value)
end

--[=[
	@within FlagManager
	@method RegisterFlag
	Registers a flag to the FlagManager service.

	@param flag FlagStruct -- The flag schema to register.
]=]
function FlagsManager:RegisterFlag(flag: FlagStruct)
	assert(typeof(flag.Name) == "string", "Flag missing property: 'Name', of type: string")
	assert(typeof(flag.Type) == "string" or typeof(flag.Type) == "table", "Flag missing property: 'Type', of type: string | { string }")
	assert(typeof(flag.IsDynamic) == "boolean", "Flag missing property: 'IsDynamic', of type: boolean")

	schema[flag.Name] = flag

	manager:Set(flag.Name, {
		Name = flag.Name,
		Value = if flag.IsDynamic then Serializer.Serialize(flag.Value) else flag.Value,
		IsDynamic = flag.IsDynamic,
	})
end

--- Starts the FlagManager service and initializes all passed flags.
function FlagManager:Start(schema: FlagSchema)
	Serializer.RegisterDefaultSerializers()

	for name, flag in schema do
		self:RegisterFlag(flag)
	end
end

----------------------------------------------------------------------------------------------------------------------------------------
-- End
----------------------------------------------------------------------------------------------------------------------------------------

return FlagManager
