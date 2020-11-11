# optimized parsing functions, copied from julia/base/parse.jl

import Base: tryparse, tryparse_internal

function tryparse(::Type{Float64}, s::DenseStringViewAndSub)
    hasvalue, val = ccall(:jl_try_substrtod, Tuple{Bool, Float64},
                          (Ptr{UInt8},Csize_t,Csize_t), s, 0, sizeof(s))
    hasvalue ? val : nothing
end
function tryparse_internal(::Type{Float64}, s::DenseStringViewAndSub, startpos::Int, endpos::Int)
    hasvalue, val = ccall(:jl_try_substrtod, Tuple{Bool, Float64},
                          (Ptr{UInt8},Csize_t,Csize_t), s, startpos-1, endpos-startpos+1)
    hasvalue ? val : nothing
end
function tryparse(::Type{Float32}, s::DenseStringViewAndSub)
    hasvalue, val = ccall(:jl_try_substrtof, Tuple{Bool, Float32},
                          (Ptr{UInt8},Csize_t,Csize_t), s, 0, sizeof(s))
    hasvalue ? val : nothing
end
function tryparse_internal(::Type{Float32}, s::DenseStringViewAndSub, startpos::Int, endpos::Int)
    hasvalue, val = ccall(:jl_try_substrtof, Tuple{Bool, Float32},
                          (Ptr{UInt8},Csize_t,Csize_t), s, startpos-1, endpos-startpos+1)
    hasvalue ? val : nothing
end

function tryparse_internal(::Type{Complex{T}}, s::DenseStringViewAndSub, i::Int, e::Int, raise::Bool) where {T<:Real}
    # skip initial whitespace
    while i ≤ e && isspace(s[i])
        i = nextind(s, i)
    end
    if i > e
        raise && throw(ArgumentError("input string is empty or only contains whitespace"))
        return nothing
    end

    # find index of ± separating real/imaginary parts (if any)
    i₊ = something(findnext(in(('+','-')), s, i), 0)
    if i₊ == i # leading ± sign
        i₊ = something(findnext(in(('+','-')), s, i₊+1), 0)
    end
    if i₊ != 0 && s[i₊-1] in ('e','E') # exponent sign
        i₊ = something(findnext(in(('+','-')), s, i₊+1), 0)
    end

    # find trailing im/i/j
    iᵢ = something(findprev(in(('m','i','j')), s, e), 0)
    if iᵢ > 0 && s[iᵢ] == 'm' # im
        iᵢ -= 1
        if s[iᵢ] != 'i'
            raise && throw(ArgumentError("expected trailing \"im\", found only \"m\""))
            return nothing
        end
    end

    if i₊ == 0 # purely real or imaginary value
        if iᵢ > i && !(iᵢ == i+1 && s[i] in ('+','-')) # purely imaginary (not "±inf")
            x = tryparse_internal(T, s, i, iᵢ-1, raise)
            x === nothing && return nothing
            return Complex{T}(zero(x),x)
        else # purely real
            x = tryparse_internal(T, s, i, e, raise)
            x === nothing && return nothing
            return Complex{T}(x)
        end
    end

    if iᵢ < i₊
        raise && throw(ArgumentError("missing imaginary unit"))
        return nothing # no imaginary part
    end

    # parse real part
    re = tryparse_internal(T, s, i, i₊-1, raise)
    re === nothing && return nothing

    # parse imaginary part
    im = tryparse_internal(T, s, i₊+1, iᵢ-1, raise)
    im === nothing && return nothing

    return Complex{T}(re, s[i₊]=='-' ? -im : im)
end

function tryparse_internal(::Type{Bool}, sbuff::DenseStringViewAndSub,
        startpos::Int, endpos::Int, base::Integer, raise::Bool)
    if isempty(sbuff)
        raise && throw(ArgumentError("input string is empty"))
        return nothing
    end

    if isnumeric(sbuff[1])
        intres = tryparse_internal(UInt8, sbuff, startpos, endpos, base, false)
        (intres == 1) && return true
        (intres == 0) && return false
        raise && throw(ArgumentError("invalid Bool representation: $(repr(sbuff))"))
    end

    orig_start = startpos
    orig_end   = endpos

    # Ignore leading and trailing whitespace
    while isspace(sbuff[startpos]) && startpos <= endpos
        startpos = nextind(sbuff, startpos)
    end
    while isspace(sbuff[endpos]) && endpos >= startpos
        endpos = prevind(sbuff, endpos)
    end

    len = endpos - startpos + 1
    p   = pointer(sbuff) + startpos - 1
    GC.@preserve sbuff begin
        (len == 4) && (0 == Base._memcmp(p, "true", 4)) && (return true)
        (len == 5) && (0 == Base._memcmp(p, "false", 5)) && (return false)
    end

    if raise
        substr = SubString(sbuff, orig_start, orig_end) # show input string in the error to avoid confusion
        if all(isspace, substr)
            throw(ArgumentError("input string only contains whitespace"))
        else
            throw(ArgumentError("invalid Bool representation: $(repr(substr))"))
        end
    end
    return nothing
end