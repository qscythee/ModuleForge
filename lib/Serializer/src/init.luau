----------------------------------------------------------------------------------------------------------------------------------------

-- Authors: Matthew (@qscythee)
-- March 04, 2025
--[=[
	@class Serializer
]=]

----------------------------------------------------------------------------------------------------------------------------------------

-- Vars
local defaultsRegistered = false

-- Types

--- @within Serializer
--- @type Dict <T>{ [string]: T }
export type Dict<T = unknown> = { [string]: T }

--- @within Serializer
--- @type Array <T>{ T }
export type Array<T = unknown> = { T }

--- @within Serializer
--- @type Primitive boolean | number | string | Dict<Primitive> | Array<Primitive>
export type Primitive = boolean | number | string | Dict<Primitive> | Array<Primitive>

--- @within Serializer
--- @type Serializable Primitive | Enum | Color3 | ColorSequence | ColorSequenceKeypoint | NumberRange | NumberSequence | NumberSequenceKeypoint | UDim | UDim2 | Vector2 | Vector3 | CFrame | Rect
export type Serializable =
	Primitive
	| Enum
	| Color3
	| ColorSequence
	| ColorSequenceKeypoint
	| NumberRange
	| NumberSequence
	| NumberSequenceKeypoint
	| UDim
	| UDim2
	| Vector2
	| Vector3
	| CFrame
	| Rect

export type SerializableType =
	"number"
	| "string"
	| "boolean"
	| "table"
	| "Enum"
	| "Color3"
	| "ColorSequence"
	| "ColorSequenceKeypoint"
	| "NumberRange"
	| "NumberSequence"
	| "NumberSequenceKeypoint"
	| "UDim"
	| "UDim2"
	| "Vector2"
	| "Vector3"
	| "CFrame"
	| "Rect"

--- @within Serializer
--- @type SerEnum { Type: "Enum", Name: string, Value: number | string }
export type SerEnum = {
	Type: "Enum",
	Name: string,
	Value: number | string,
}

--- @within Serializer
--- @type SerColor3 { Type: "Color3", Value: { R: number, G: number, B: number } }
export type SerColor3 = {
	Type: "Color3",
	Value: {
		R: number,
		G: number,
		B: number,
	},
}

--- @within Serializer
--- @type SerColorKeypoint { Type: "ColorSequenceKeypoint", Value: { Time: number, Value: SerColor3 } }
export type SerColorKeypoint = {
	Type: "ColorSequenceKeypoint",
	Value: {
		Time: number,
		Value: SerColor3,
	},
}

--- @within Serializer
--- @type SerColorSequence { Type: "ColorSequence", Value: Array<SerColorKeypoint> }
export type SerColorSequence = {
	Type: "ColorSequence",
	Value: Array<SerColorKeypoint>,
}

--- @within Serializer
--- @type SerNumberRange { Type: "NumberRange", Value: { Min: number, Max: number } }
export type SerNumberRange = {
	Type: "NumberRange",
	Value: {
		Min: number,
		Max: number,
	},
}

--- @within Serializer
--- @type SerNumberKeypoint { Type: "NumberSequenceKeypoint", Value: { Time: number, Value: number } }
export type SerNumberKeypoint = {
	Type: "NumberSequenceKeypoint",
	Value: {
		Time: number,
		Value: number,
	},
}

--- @within Serializer
--- @type SerNumberSequence { Type: "NumberSequence", Value: Array<SerNumberKeypoint> }
export type SerNumberSequence = {
	Type: "NumberSequence",
	Value: Array<SerNumberKeypoint>,
}

--- @within Serializer
--- @type SerUDim { Type: "UDim", Value: { Scale: number, Offset: number } }
export type SerUDim = {
	Type: "UDim",
	Value: {
		Scale: number,
		Offset: number,
	},
}

--- @within Serializer
--- @type SerUDim2 { Type: "UDim2", Value: { X: SerUDim, Y: SerUDim } }
export type SerUDim2 = {
	Type: "UDim2",
	Value: {
		X: SerUDim,
		Y: SerUDim,
	},
}

--- @within Serializer
--- @type SerVector2 { Type: "Vector2", Value: { X: number, Y: number } }
export type SerVector2 = {
	Type: "Vector2",
	Value: {
		X: number,
		Y: number,
	},
}

--- @within Serializer
--- @type SerVector3 { Type: "Vector3", Value: { X: number, Y: number, Z: number } }
export type SerVector3 = {
	Type: "Vector3",
	Value: {
		X: number,
		Y: number,
		Z: number,
	},
}

--- @within Serializer
--- @type SerCFrame { Type: "CFrame", Components: Array<number> }
export type SerCFrame = {
	Type: "CFrame",
	Components: Array<number>,
}

--- @within Serializer
--- @type SerRect { Type: "Rect", Value: { Height: SerVector2, Width: SerVector2, Min: SerVector2, Max: SerVector2 } }
export type SerRect = {
	Type: "Rect",
	Value: {
		Height: SerVector2,
		Width: SerVector2,
		Min: SerVector2,
		Max: SerVector2,
	},
}

--- @within Serializer
--- @type SerCustom <T>{ Type: "Custom", Value: T | Primitive }
export type SerCustom<T> = {
	Type: "Custom",
	Value: T | Primitive,
}

--- @within Serializer
--- @type Serialized Primitive | SerEnum | SerColor3 | SerColorKeypoint | SerColorSequence | SerNumberRange | SerNumberKeypoint | SerNumberSequence | SerUDim | SerUDim2 | SerVector2 | SerVector3 | SerCFrame | SerRect | SerCustom
export type Serialized = {
	Name: string,
	Value: Primitive
		| SerEnum
		| SerColor3
		| SerColorKeypoint
		| SerColorSequence
		| SerNumberRange
		| SerNumberKeypoint
		| SerNumberSequence
		| SerUDim
		| SerUDim2
		| SerVector2
		| SerVector3
		| SerCFrame
		| SerRect
		| SerCustom,
}

----------------------------------------------------------------------------------------------------------------------------------------
-- Module
----------------------------------------------------------------------------------------------------------------------------------------

local Serializer = {
	Serializers = {},
	Deserializers = {},
}

--[=[
	@within Serializer
	@function GetSerializer
	@param type string -- The type of the data to serialize.
	@return (data: any) -> Serialized -- The serializer callback.
]=]
function Serializer.GetSerializer(type: string): (data: any) -> Serialized
	return Serializer.Serializers[type]
end

--[=[
	@within Serializer
	@function GetDeserializer
	@param type string -- The type of the data to deserialize.
	@return (data: Serialized) -> any -- The deserializer callback.
]=]
function Serializer.GetDeserializer(type: string): (data: Serialized) -> any
	return Serializer.Serializers[type]
end

--[=[
	@within Serializer
	@function RegisterSerializer
	@param type string -- The type of the data (used as the key) to serialize.
	@param serializer (data: any) -> Serialized -- The callback function that serializes the data.
	@param overwrite boolean? -- Whether to overwrite the deserializer if it already exists.
]=]
function Serializer.RegisterSerializer(type: string, serializer: (data: any) -> Serialized, overwrite: boolean?)
	if Serializer.Serializers[type] and not overwrite then warn(debug.traceback(`Serializer for type '{type}' already exists!`)) end
	Serializer.Serializers[type] = serializer
end

--[=[
	@within Serializer
	@function RegisterDeserializer
	@param type string -- The type of the data (used as the key) to deserialize.
	@param deserializer (data: Serialized) -> any -- The callback function that deserializes the data.
	@param overwrite boolean? -- Whether to overwrite the deserializer if it already exists.
]=]
function Serializer.RegisterDeserializer(type: string, deserializer: (data: Serialized) -> any, overwrite: boolean?)
	if Serializer.Deserializers[type] and not overwrite then warn(debug.traceback(`Deserializer for type '{type}' already exists!`)) end
	Serializer.Deserializers[type] = deserializer
end

--[=[
	@within Serializer
	@function Serialize
	@param data Serializable -- The data to serialize.
	@return Serialized -- The serialized data.
]=]
function Serializer.Serialize(data: Serializable): Serialized
	local serializer = if Serializer.Serializers[typeof(data)]
		then Serializer.Serializers[typeof(data)]
		else Serializer.Serializers[data.Type]
	if serializer then return serializer(data) end
	return data
end

--[=[
	@within Serializer
	@function SerializeMultiple
	@param ... Serializable -- The data to serialize.
	@return ...Serialized -- The serialized data.
]=]
function Serializer.SerializeMultiple(...: Serializable): ...Serialized
	local serialized = {}
	for i, data in table.pack(...) do
		serialized[i] = Serializer.Serialize(data)
	end
	return table.unpack(serialized)
end

--[=[
	@within Serializer
	@function Deserialize
	@param data Serialized -- The data to deserialize.
	@return Serializable -- The deserialized data.
]=]
function Serializer.Deserialize(data: Serialized): Serializable
	assert(data.Type, "Serialized data must have a 'Type' field.")
	local deserializer = Serializer.Deserializers[data.Type]
	if deserializer then return deserializer(data.Value) end
	return data.Value
end

--[=[
	@within Serializer
	@function DeserializeMultiple
	@param ... Serialized -- The data to deserialize.
	@return ...Serializable -- The deserialized data.
]=]
function Serializer.DeserializeMultiple(...: Serialized): ...Serializable
	local deserialized = {}
	for i, data in table.pack(...) do
		deserialized[i] = Serializer.Deserialize(data)
	end
	return table.unpack(deserialized)
end

--[=[
	@within Serializer
	@function RegisterDefaultSerializers
	Registers default serializers for the following types:
	* Enum
	* Color3
	* ColorSequenceKeypoint
	* ColorSequence
	* NumberRange
	* NumberSequenceKeypoint
	* NumberSequence
	* UDim
	* UDim2
	* Vector2
	* Vector3
	* CFrame
	* Rect
]=]
function Serializer.RegisterDefaultSerializers()
	if defaultsRegistered then
		warn(debug.traceback("Default serializers have already been registered!"))
		return
	end

	-- Enum ----------------------------------------------------------------
	Serializer.RegisterSerializer("Enum", function(data: Enum): SerEnum
		return {
			Type = "Enum",
			EnumType = tostring(data.EnumType),
			Name = data.Name,
		}
	end)

	Serializer.RegisterDeserializer("Enum", function(data: SerEnum): Enum
		local ok, enum = pcall(function()
			return Enum[data.EnumType]:FromName(data.Name)
		end)
		if not ok then
			warn(debug.traceback(`Failed to deserialize Enum {data.EnumType}.{data.Name}: {enum}`))
			return nil
		end
		return enum
	end)

	-- Color3 --------------------------------------------------------------
	Serializer.RegisterSerializer("Color3", function(data: Color3): SerColor3
		return {
			Type = "Color3",
			Value = {
				R = data.R,
				G = data.G,
				B = data.B,
			},
		}
	end)

	Serializer.RegisterDeserializer("Color3", function(data: SerColor3): Color3
		return Color3.new(data.Value.R, data.Value.G, data.Value.B)
	end)

	-- ColorSequenceKeypoint ----------------------------------------------
	Serializer.RegisterSerializer("ColorSequenceKeypoint", function(data: ColorSequenceKeypoint): SerColorKeypoint
		return {
			Type = "ColorSequenceKeypoint",
			Value = {
				Time = data.Time,
				Value = Serializer.Serialize(data.Value),
			},
		}
	end)

	Serializer.RegisterDeserializer("ColorSequenceKeypoint", function(data: SerColorKeypoint): ColorSequenceKeypoint
		return ColorSequenceKeypoint.new(data.Value.Time, Serializer.Deserialize(data.Value.Value))
	end)

	-- ColorSequence -------------------------------------------------------
	Serializer.RegisterSerializer("ColorSequence", function(data: ColorSequence): SerColorSequence
		local serialized = {}
		for i, keypoint in ipairs(data.Keypoints) do
			serialized[i] = Serializer.Serialize(keypoint)
		end
		return {
			Type = "ColorSequence",
			Value = serialized,
		}
	end)

	Serializer.RegisterDeserializer("ColorSequence", function(data: SerColorSequence): ColorSequence
		local deserialized = {}
		for i, keypoint in ipairs(data.Value) do
			deserialized[i] = Serializer.Deserialize(keypoint)
		end
		return ColorSequence.new(deserialized)
	end)

	-- NumberRange ---------------------------------------------------------
	Serializer.RegisterSerializer("NumberRange", function(data: NumberRange): SerNumberRange
		return {
			Type = "NumberRange",
			Value = {
				Min = data.Min,
				Max = data.Max,
			},
		}
	end)

	Serializer.RegisterDeserializer("NumberRange", function(data: SerNumberRange): NumberRange
		return NumberRange.new(data.Value.Min, data.Value.Max)
	end)

	-- NumberSequenceKeypoint ---------------------------------------------
	Serializer.RegisterSerializer("NumberSequenceKeypoint", function(data: NumberSequenceKeypoint): SerNumberKeypoint
		return {
			Type = "NumberSequenceKeypoint",
			Value = {
				Time = data.Time,
				Value = data.Value,
			},
		}
	end)

	Serializer.RegisterDeserializer("NumberSequenceKeypoint", function(data: SerNumberKeypoint): NumberSequenceKeypoint
		return NumberSequenceKeypoint.new(data.Value.Time, data.Value.Value)
	end)

	-- NumberSequence ------------------------------------------------------
	Serializer.RegisterSerializer("NumberSequence", function(data: NumberSequence): SerNumberSequence
		local serialized = {}
		for i, keypoint in ipairs(data.Keypoints) do
			serialized[i] = Serializer.Serialize(keypoint)
		end
		return {
			Type = "NumberSequence",
			Value = serialized,
		}
	end)

	Serializer.RegisterDeserializer("NumberSequence", function(data: SerNumberSequence): NumberSequence
		local deserialized = {}
		for i, keypoint in ipairs(data.Value) do
			deserialized[i] = Serializer.Deserialize(keypoint)
		end
		return NumberSequence.new(deserialized)
	end)

	-- UDim ---------------------------------------------------------------
	Serializer.RegisterSerializer("UDim", function(data: UDim): SerUDim
		return {
			Type = "UDim",
			Value = {
				Scale = data.Scale,
				Offset = data.Offset,
			},
		}
	end)

	Serializer.RegisterDeserializer("UDim", function(data: SerUDim): UDim
		return UDim.new(data.Value.Scale, data.Value.Offset)
	end)

	-- UDim2 --------------------------------------------------------------
	Serializer.RegisterSerializer("UDim2", function(data: UDim2): SerUDim2
		return {
			Type = "UDim2",
			Value = {
				X = Serializer.Serialize(data.X),
				Y = Serializer.Serialize(data.Y),
			},
		}
	end)

	Serializer.RegisterDeserializer("UDim2", function(data: SerUDim2): UDim2
		return UDim2.new(Serializer.Deserialize(data.X), Serializer.Deserialize(data.Y))
	end)

	-- Vector2 ------------------------------------------------------------
	Serializer.RegisterSerializer("Vector2", function(data: Vector2): SerVector2
		return {
			Type = "Vector2",
			Value = {
				X = data.X,
				Y = data.Y,
			},
		}
	end)

	Serializer.RegisterDeserializer("Vector2", function(data: SerVector2): Vector2
		return Vector2.new(data.Value.X, data.Value.Y)
	end)

	-- Vector3 ------------------------------------------------------------
	Serializer.RegisterSerializer("Vector3", function(data: Vector3): SerVector3
		return {
			Type = "Vector3",
			Value = {
				X = data.X,
				Y = data.Y,
				Z = data.Z,
			},
		}
	end)

	Serializer.RegisterDeserializer("Vector3", function(data: SerVector3): Vector3
		return Vector3.new(data.Value.X, data.Value.Y, data.Value.Z)
	end)

	-- CFrame -------------------------------------------------------------
	Serializer.RegisterSerializer("CFrame", function(data: CFrame): SerCFrame
		return {
			Type = "CFrame",
			Components = table.pack(data:components()),
		}
	end)

	Serializer.RegisterDeserializer("CFrame", function(data: SerCFrame): CFrame
		return CFrame.new(table.unpack(data.Components))
	end)

	-- Rect ---------------------------------------------------------------
	Serializer.RegisterSerializer("Rect", function(data: Rect): SerRect
		return {
			Type = "Rect",
			Value = {
				Height = data.Height,
				Width = data.Width,
				Min = Serializer.Serialize(data.Min),
				Max = Serializer.Serialize(data.Max),
			},
		}
	end)

	Serializer.RegisterDeserializer("Rect", function(data: SerRect): Rect
		return Rect.new(data.Height, data.Width, Serializer.Deserialize(data.Min), Serializer.Deserialize(data.Max))
	end)
end

return Serializer
