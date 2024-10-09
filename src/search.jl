# optimized string routines copied from julia/base/strings/search.jl

nothing_sentinel(x) = iszero(x) ? nothing : x

function Base.findnext(pred::Base.Fix2{<:Union{typeof(isequal),typeof(==)},<:AbstractChar},
                  s::StringViewAndSub, i::Integer)
    if i < 1 || i > sizeof(s)
        i == sizeof(s) + 1 && return nothing
        throw(BoundsError(s, i))
    end
    @inbounds isvalid(s, i) || Base.string_index_err(s, i)
    c = pred.x
    c ≤ '\x7f' && return nothing_sentinel(Base._search(s, c % UInt8, i))
    while true
        i = Base._search(s, Base.first_utf8_byte(c), i)
        i == 0 && return nothing
        pred(s[i]) && return i
        i = nextind(s, i)
    end
end

function Base._search(a::StringViewAndSub, b::Union{Int8,UInt8}, i::Integer = 1)
    if i < 1
        throw(BoundsError(a, i))
    end
    n = sizeof(a)
    if i > n
        return i == n+1 ? 0 : throw(BoundsError(a, i))
    end
    if a isa DenseStringViewAndSub
        p = pointer(a)
        q = GC.@preserve a ccall(:memchr, Ptr{UInt8}, (Ptr{UInt8}, Int32, Csize_t), p+i-1, b, n-i+1)
        return q == C_NULL ? 0 : Int(q-p+1)
    else
        _i = Int(i)
        while true
            codeunit(a,_i) == b && return _i
            (_i += 1) > n && break
        end
        return 0
    end
end

function Base.findprev(pred::Base.Fix2{<:Union{typeof(isequal),typeof(==)},<:AbstractChar},
                  s::StringViewAndSub, i::Integer)
    c = pred.x
    c ≤ '\x7f' && return nothing_sentinel(Base._rsearch(s, c % UInt8, i))
    b = Base.first_utf8_byte(c)
    while true
        i = Base._rsearch(s, b, i)
        i == 0 && return nothing
        pred(s[i]) && return i
        i = prevind(s, i)
    end
end

function Base._rsearch(a::StringViewAndSub, b::Union{Int8,UInt8}, i::Integer = sizeof(a))
    if i < 1
        return i == 0 ? 0 : throw(BoundsError(a, i))
    end
    n = sizeof(a)
    if i > n
        return i == n+1 ? 0 : throw(BoundsError(a, i))
    end
    if a isa DenseStringViewAndSub
        p = pointer(a)
        q = GC.@preserve a ccall(:memrchr, Ptr{UInt8}, (Ptr{UInt8}, Int32, Csize_t), p, b, i)
        return q == C_NULL ? 0 : Int(q-p+1)
    else
        _i = Int(i)
        while true
            codeunit(a,_i) == b && return _i
            (_i -= 1) < 1 && break
        end
        return 0
    end
end

# The following functions require julia#37283 in Julia 1.6, which
# allow us to search byte arrays (applied to codeunits(s)).
@static if VERSION ≥ v"1.6.0-DEV.1341"
    # Split into two identical methods to avoid pirating Base's methods, leading to ~370 invalidations.
    function Base._searchindex(s::StringViewAndSub, t::Union{StringViewAndSub,StringAndSub}, i::Integer)
        searchindex_internal(s, t, i)
    end

    function Base._searchindex(s::Union{StringViewAndSub,StringAndSub}, t::StringViewAndSub, i::Integer)
        searchindex_internal(s, t, i)
    end

    function searchindex_internal(s::Union{StringViewAndSub,StringAndSub}, t::Union{StringViewAndSub,StringAndSub}, i::Integer)
        # Check for fast case of a single byte
        lastindex(t) == 1 && return something(findnext(isequal(t[1]), s, i), 0)
        Base._searchindex(codeunits(s), codeunits(t), i)
    end

    function Base._rsearchindex(s::StringViewAndSub, t::Union{StringViewAndSub,StringAndSub}, i::Integer)
        rsearchindex_internal(s, t, i)
    end

    function Base._rsearchindex(s::Union{StringViewAndSub,StringAndSub}, t::StringViewAndSub, i::Integer)
        rsearchindex_internal(s, t, i)
    end

    function rsearchindex_internal(s::Union{StringViewAndSub,StringAndSub}, t::Union{StringViewAndSub,StringAndSub}, i::Integer)
        # Check for fast case of a single byte
        if lastindex(t) == 1
            return something(findprev(isequal(t[1]), s, i), 0)
        elseif lastindex(t) != 0
            j = i ≤ ncodeunits(s) ? nextind(s, i)-1 : i
            return Base._rsearchindex(codeunits(s), codeunits(t), j)
        elseif i > sizeof(s)
            return 0
        elseif i == 0
            return 1
        else
            return i
        end
    end
end
