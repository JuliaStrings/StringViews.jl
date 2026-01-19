# other optimized string routines copied from julia/base/strings/util.jl

function Base.startswith(
        a::Union{DenseStringViewAndSub,StringAndSub},
        b::DenseStringViewAndSub
    )
    _startswith(a, b)
end

function Base.startswith(
        a::DenseStringViewAndSub,
        b::Union{DenseStringViewAndSub,StringAndSub}
    )
    _startswith(a, b)
end

function _startswith(a, b)
    cub = ncodeunits(b)
    if ncodeunits(a) < cub
        false
    elseif _memcmp(a, b, sizeof(b)) == 0
        nextind(a, cub) == cub + 1
    else
        false
    end
end

function Base.endswith(
        a::Union{DenseStringViewAndSub,StringAndSub},
        b::DenseStringViewAndSub
    )
    _endswith(a, b)
end

function Base.endswith(
        a::DenseStringViewAndSub,
        b::Union{DenseStringViewAndSub,StringAndSub}
    )
    _endswith(a, b)
end

function _endswith(a, b)
    cub = ncodeunits(b)
    astart = ncodeunits(a) - ncodeunits(b) + 1
    if astart < 1
        false
    elseif GC.@preserve(a, _memcmp(pointer(a, astart), b, sizeof(b))) == 0
        thisind(a, astart) == astart
    else
        false
    end
end

function Base.chomp(s::StringViewAndSub)
    i = lastindex(s)
    if i < 1 || codeunit(s,i) != 0x0a
        return @inbounds SubString(s, 1, i)
    elseif i < 2 || codeunit(s,i-1) != 0x0d
        return @inbounds SubString(s, 1, prevind(s, i))
    else
        return @inbounds SubString(s, 1, prevind(s, i-1))
    end
end


# support replace via JuliaLang/julia#48625
if isdefined(Base, :_replace_)
    Base.replace(io::IO, s::DenseStringViewAndSub, pat_f::Pair...; count=typemax(Int)) =
        Base._replace_(io, s, pat_f, Int(count))

    function Base.replace(s::DenseStringViewAndSub, pat_f::Pair...; count=typemax(Int))
        # don't simply call Base._replace_(s, pat_f, Int(count)),
        # to avoid type-instability for empty-replacements case: always return String
        # (remove when #50424 is merged)
        buf = IOBuffer(sizehint=floor(Int, 1.2sizeof(s)))
        return String(take!(replace(buf, s, pat_f...; count=count)))
    end
else
    Base.replace(str::DenseStringViewAndSub, pat_repl::Pair{<:AbstractChar}; count::Integer=typemax(Int)) =
        replace(str, isequal(first(pat_repl)) => last(pat_repl); count=count)

    Base.replace(str::DenseStringViewAndSub, pat_repl::Pair{<:Union{Tuple{Vararg{AbstractChar}},
                                                AbstractVector{<:AbstractChar},Set{<:AbstractChar}}};
            count::Integer=typemax(Int)) =
        replace(str, in(first(pat_repl)) => last(pat_repl), count=count)

    import Base: _pat_replacer, _free_pat_replacer

    function Base.replace(str::DenseStringViewAndSub, pat_repl::Pair; count::Integer=typemax(Int))
        pattern, repl = pat_repl
        count == 0 && return str
        count < 0 && throw(DomainError(count, "`count` must be non-negative."))
        n = 1
        e = lastindex(str)
        i = a = firstindex(str)
        pattern = _pat_replacer(pattern)
        r = something(findnext(pattern,str,i), 0)
        j, k = first(r), last(r)
        if j == 0
            _free_pat_replacer(pattern)
            return str
        end
        out = IOBuffer(sizehint=floor(Int, 1.2sizeof(str)))
        while j != 0
            if i == a || i <= k
                GC.@preserve str unsafe_write(out, pointer(str, i), UInt(j-i))
                Base._replace(out, repl, str, r, pattern)
            end
            if k < j
                i = j
                j > e && break
                k = nextind(str, j)
            else
                i = k = nextind(str, k)
            end
            r = something(findnext(pattern,str,k), 0)
            r === 0:-1 || n == count && break
            j, k = first(r), last(r)
            n += 1
        end
        _free_pat_replacer(pattern)
        write(out, SubString(str,i))
        String(take!(out))
    end
end
