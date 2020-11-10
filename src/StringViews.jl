"""
This module implements a new type of `AbstractString`, a `StringView`,
that provides a string representation of any underlying array of bytes
(any `AbstractVector{UInt8}`), interpreted as UTF-8 encoded Unicode data.

Unlike Julia's built-in `String` type (which also wraps UTF-8 data), the
`StringView` type is a copy-free wrap of *any* `AbstractVector{UInt8}`
instance, and does not take "ownership" or modify the arrray.   Otherwise,
a `StringView` is intended to be usable in any context where you might
have otherwise used `String`.
"""
module StringViews
export StringView

"""
    StringView{T<:AbstractVector{UInt8}} <: AbstractString

`StringView(array)` creates an `AbstractString` representation of
any `array` of `UInt8` data, interpreted as UTF-8 encoded Unicode.
It does *not* make a copy of `array`.
"""
struct StringView{T} <: AbstractString where {T<:AbstractVector{UInt8}}
    data::T
end

const DenseStringView = StringView{<:Union{DenseVector{UInt8},<:Base.FastContiguousSubArray{UInt8,1,<:DenseVector{UInt8}}}}

Base.Vector{UInt8}(s::StringView{Vector{UInt8}}) = s.data
Base.Vector{UInt8}(s::StringView) = Vector{UInt8}(s.data)
Base.Array{UInt8}(s::StringView) = Vector{UInt8}(s)
Base.String(s::StringView) = String(copyto!(Base.StringVector(length(s.data)), s.data))
StringView(s::StringView) = s
StringView(s::String) = StringView(codeunits(s))

Base.Symbol(s::DenseStringView) =
    return ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), s, ncodeunits(s))

Base.pointer(s::DenseStringView) = pointer(s.data)
Base.pointer(s::DenseStringView, i::Integer) = pointer(s.data, i)
Base.unsafe_convert(::Type{Ptr{UInt8}}, s::DenseStringView) = pointer(s.data)
Base.unsafe_convert(::Type{Ptr{Int8}}, s::DenseStringView) = convert(Ptr{Int8}, pointer(s.data))

Base.sizeof(s::StringView) = sizeof(s.data)
Base.ncodeunits(s::StringView) = length(s.data)
Base.codeunit(s::StringView) = UInt8
Base.@propagate_inbounds Base.codeunit(s::StringView, i::Integer) = s.data[i]
Base.codeunits(s::StringView) = s.data

_memcmp(a, b, len) =
    ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), a, b, len % Csize_t) % Int
function _cmp(a, b)
    al, bl = sizeof(a), sizeof(b)
    c = _memcmp(a, b, min(al,bl))
    return c < 0 ? -1 : c > 0 ? +1 : cmp(al,bl)
end
Base.cmp(a::DenseStringView, b::DenseStringView) = _cmp(a, b)
Base.cmp(a::DenseStringView, b::String) = _cmp(a, b)
Base.cmp(a::String, b::DenseStringView) = _cmp(a, b)
Base.:(==)(s1::StringView, s2::StringView) = s1.data == s2.data
function Base.:(==)(a::String, b::StringView)
    al = sizeof(a)
    return al == sizeof(b) && 0 == _memcmp(a, b, al)
end
Base.:(==)(s1::StringView, s2::String) = s2 == s1

Base.typemin(::Type{StringView{Vector{UInt8}}}) = StringView(Vector{UInt8}(undef,0))
Base.typemin(::T) where {T<:StringView} = typemin(T)

Base.isvalid(s::DenseStringView) = ccall(:u8_isvalid, Int32, (Ptr{UInt8}, Int), s, sizeof(s)) ≠ 0
Base.isvalid(::Type{String}, s::StringView) = isvalid(s)

function Base.isascii(s::StringView)
    @inbounds for i = 1:ncodeunits(s)
        codeunit(s, i) >= 0x80 && return false
    end
    return true
end

write(io::IO, s::StringView) = write(io, s.data)
print(io::IO, s::StringView) = (write(io, s); nothing)

Base.@propagate_inbounds Base.thisind(s::StringView, i::Int) = Base._thisind_str(s, i)
Base.@propagate_inbounds Base.nextind(s::String, i::Int) = Base._nextind_str(s, i)
Base.isvalid(s::StringView, i::Int) = checkbounds(Bool, s, i) && thisind(s, i) == i

function Base.hash(s::DenseStringView, h::UInt)
    h += Base.memhash_seed
    ccall(Base.memhash, UInt, (Ptr{UInt8}, Csize_t, UInt32), s.data, length(s.data), h % UInt32) + h
end

include("decoding.jl")
include("regex.jl")

end # module
