"""
This module implements a new type of `AbstractString`, a `StringView`,
that provides a string representation of any underlying array of bytes
(any `AbstractVector{UInt8}`), interpreted as UTF-8 encoded Unicode data.

Unlike Julia's built-in `String` type (which also wraps UTF-8 data), the
`StringView` type is a copy-free wrap of *any* `AbstractVector{UInt8}`
instance, and does not take "ownership" of or modify the array.   Otherwise,
a `StringView` is intended to be usable in any context where you might
have otherwise used `String`.
"""
module StringViews
export StringView, SVRegexMatch

"""
    StringView{T<:AbstractVector{UInt8}} <: AbstractString

`StringView(array)` creates an `AbstractString` representation of
any `array` of `UInt8` data, interpreted as UTF-8 encoded Unicode.
It does *not* make a copy of or modify `array`.

`StringView(buf::IOBuffer)` returns a string view of the
current contents of the `buf`, equivalent to `String(take!(buf))`
but without making a copy.   `StringView(buf::IOBuffer, range)`
is a view of the bytes `range` (defaults to `1:position(buf)-1`)
in the buffer.
"""
struct StringView{T<:AbstractVector{UInt8}} <: AbstractString
    data::T
end

const DenseStringView = StringView{<:Union{DenseVector{UInt8},<:Base.FastContiguousSubArray{UInt8,1,<:DenseVector{UInt8}}}}
const StringAndSub = Union{String,SubString{String}}
const StringViewAndSub = Union{StringView,SubString{<:StringView}}
const DenseStringViewAndSub = Union{DenseStringView,SubString{<:DenseStringView}}

Base.Vector{UInt8}(s::StringView{Vector{UInt8}}) = s.data
Base.Vector{UInt8}(s::StringViewAndSub) = Vector{UInt8}(codeunits(s))
Base.Array{UInt8}(s::StringViewAndSub) = Vector{UInt8}(s)
Base.String(s::StringViewAndSub) = String(copyto!(Base.StringVector(ncodeunits(s)), codeunits(s)))
StringView(s::StringView) = s
StringView(s::String) = StringView(codeunits(s))

# iobuffer constructor (note that buf.data is always 1-based)
StringView(buf::IOBuffer, r::OrdinalRange{<:Integer,<:Integer}=Base.OneTo(buf.ptr-1)) =
    StringView(@view buf.data[r])

Base.copy(s::StringView) = StringView(copy(s.data))

Base.Symbol(s::DenseStringViewAndSub) =
    return ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), s, ncodeunits(s))

Base.pointer(s::DenseStringView) = pointer(s.data)
Base.pointer(s::DenseStringView, i::Integer) = pointer(s.data, i)
Base.pointer(x::SubString{<:DenseStringView}) = pointer(x.string) + x.offset
Base.pointer(x::SubString{<:DenseStringView}, i::Integer) = pointer(x.string) + x.offset + (i-1)
Base.unsafe_convert(::Type{Ptr{UInt8}}, s::DenseStringViewAndSub) = pointer(s)
Base.unsafe_convert(::Type{Ptr{Int8}}, s::DenseStringViewAndSub) = convert(Ptr{Int8}, pointer(s))
Base.cconvert(::Type{Ptr{UInt8}}, s::DenseStringViewAndSub) = s
Base.cconvert(::Type{Ptr{Int8}}, s::DenseStringViewAndSub) = s

Base.sizeof(s::StringView) = length(s.data)
Base.ncodeunits(s::StringView) = length(s.data)
Base.codeunit(s::StringView) = UInt8
Base.@propagate_inbounds Base.codeunit(s::StringView, i::Integer) = s.data[i]
Base.codeunits(s::StringView) = s.data
Base.codeunits(s::SubString{<:StringView}) = @view s.string.data[1+s.offset:s.offset+s.ncodeunits]

_memcmp(a, b, len) =
    ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), a, b, len % Csize_t) % Int
function _cmp(a, b)
    al, bl = sizeof(a), sizeof(b)
    c = _memcmp(a, b, min(al,bl))
    return c < 0 ? -1 : c > 0 ? +1 : cmp(al,bl)
end
Base.cmp(a::DenseStringViewAndSub, b::DenseStringViewAndSub) = _cmp(a, b)
Base.cmp(a::DenseStringViewAndSub, b::StringAndSub) = _cmp(a, b)
Base.cmp(a::StringAndSub, b::DenseStringViewAndSub) = _cmp(a, b)
Base.:(==)(s1::StringViewAndSub, s2::StringViewAndSub) = codeunits(s1) == codeunits(s2)
Base.:(==)(s1::StringAndSub, s2::StringViewAndSub) = codeunits(s1) == codeunits(s2)
function Base.:(==)(a::StringAndSub, b::DenseStringViewAndSub)
    al = sizeof(a)
    return al == sizeof(b) && 0 == _memcmp(a, b, al)
end
Base.:(==)(s1::StringViewAndSub, s2::StringAndSub) = s2 == s1

Base.typemin(::Type{StringView{Vector{UInt8}}}) = StringView(Vector{UInt8}(undef,0))
Base.typemin(::T) where {T<:StringView} = typemin(T)

Base.isvalid(s::DenseStringViewAndSub) = ccall(:u8_isvalid, Int32, (Ptr{UInt8}, Int), s, sizeof(s)) ≠ 0
Base.isvalid(s::StringViewAndSub) = all(isvalid, s)
Base.isvalid(::Type{String}, s::StringViewAndSub) = isvalid(s)

function Base.isascii(s::StringViewAndSub)
    @inbounds for i = 1:ncodeunits(s)
        codeunit(s, i) >= 0x80 && return false
    end
    return true
end

Base.write(io::IO, s::StringViewAndSub) = write(io, codeunits(s))
Base.print(io::IO, s::StringViewAndSub) = (write(io, s); nothing)

Base.@propagate_inbounds Base.thisind(s::StringViewAndSub, i::Int) = Base._thisind_str(s, i)
Base.@propagate_inbounds Base.nextind(s::StringViewAndSub, i::Int) = Base._nextind_str(s, i)
Base.isvalid(s::StringViewAndSub, i::Int) = checkbounds(Bool, s, i) && thisind(s, i) == i

function Base.hash(s::DenseStringViewAndSub, h::UInt)
    h += Base.memhash_seed
    ccall(Base.memhash, UInt, (Ptr{UInt8}, Csize_t, UInt32), s, ncodeunits(s), h % UInt32) + h
end

# each string type must implement its own reverse because it is generally
# encoding-dependent
function Base.reverse(s::StringViewAndSub)::String
    # Read characters forwards from `s` and write backwards to `out`
    out = Base._string_n(sizeof(s))
    offs = sizeof(s) + 1
    for c in s
        offs -= ncodeunits(c)
        Base.__unsafe_string!(out, c, offs)
    end
    return out
end

include("decoding.jl")
include("regex.jl")
include("parse.jl")
include("util.jl")
include("search.jl")

end # module
