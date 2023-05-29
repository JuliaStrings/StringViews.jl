# copy-free regular-expression searches on DenseStringViews, implemented
# by copying the low-level PCRE calls from julia/base/regex.jl

import Base.PCRE

function Base.occursin(r::Regex, s::DenseStringViewAndSub; offset::Integer=0)
    Base.compile(r)
    return PCRE.exec_r(r.regex, s, offset, r.match_options)
end

function Base.startswith(s::DenseStringViewAndSub, r::Regex)
    Base.compile(r)
    return PCRE.exec_r(r.regex, s, 0, r.match_options | PCRE.ANCHORED)
end

function Base.endswith(s::DenseStringViewAndSub, r::Regex)
    Base.compile(r)
    return PCRE.exec_r(r.regex, s, 0, r.match_options | PCRE.ENDANCHORED)
end

function Base.match(re::Regex, str::T, idx::Integer, add_opts::UInt32=UInt32(0)) where {T<:DenseStringViewAndSub}
    Base.compile(re)
    opts = re.match_options | add_opts
    matched, data = PCRE.exec_r_data(re.regex, str, idx-1, opts)
    if !matched
        PCRE.free_match_data(data)
        return nothing
    end
    n = div(PCRE.ovec_length(data), 2) - 1
    p = PCRE.ovec_ptr(data)
    mat = SubString(str, unsafe_load(p, 1)+1, prevind(str, unsafe_load(p, 2)+1))
    cap = Union{Nothing,SubString{T}}[unsafe_load(p,2i+1) == PCRE.UNSET ? nothing :
                                           SubString(str, unsafe_load(p,2i+1)+1,
                                           prevind(str, unsafe_load(p,2i+2)+1)) for i=1:n]
    off = Int[ unsafe_load(p,2i+1)+1 for i=1:n ]
    result = SVRegexMatch(mat, cap, unsafe_load(p,1)+1, off, re)
    PCRE.free_match_data(data)
    return result
end

Base.findnext(re::Regex, str::DenseStringViewAndSub, idx::Integer) = Base._findnext_re(re, str, idx, C_NULL)

function Base._findnext_re(re::Regex, str::DenseStringViewAndSub, idx::Integer, match_data::Ptr{Cvoid})
    if idx > nextind(str,lastindex(str))
        throw(BoundsError())
    end
    opts = re.match_options
    Base.compile(re)
    alloc = match_data == C_NULL
    if alloc
        matched, data = PCRE.exec_r_data(re.regex, str, idx-1, opts)
    else
        matched = PCRE.exec(re.regex, str, idx-1, opts, match_data)
        data = match_data
    end
    if matched
        p = PCRE.ovec_ptr(data)
        ans = (Int(unsafe_load(p,1))+1):prevind(str,Int(unsafe_load(p,2))+1)
    else
        ans = nothing
    end
    alloc && PCRE.free_match_data(data)
    return ans
end

# copied from Base.RegexMatchIterator
struct RegexMatchIterator{T<:DenseStringViewAndSub}
    regex::Regex
    string::T
    overlap::Bool
end
Base.compile(itr::RegexMatchIterator) = (Base.compile(itr.regex); itr)
Base.eltype(::Type{RegexMatchIterator{T}}) where {T<:DenseStringView} = SVRegexMatch{T}
Base.eltype(::Type{RegexMatchIterator{SubString{T}}}) where {T<:DenseStringView} = SVRegexMatch{T}
Base.IteratorSize(::Type{<:RegexMatchIterator}) = Base.SizeUnknown()

function Base.iterate(itr::RegexMatchIterator, (offset,prevempty)=(1,false))
    opts_nonempty = UInt32(PCRE.ANCHORED | PCRE.NOTEMPTY_ATSTART)
    while true
        mat = match(itr.regex, itr.string, offset,
                    prevempty ? opts_nonempty : UInt32(0))

        if mat === nothing
            if prevempty && offset <= sizeof(itr.string)
                offset = nextind(itr.string, offset)
                prevempty = false
                continue
            else
                break
            end
        else
            if itr.overlap
                if !isempty(mat.match)
                    offset = nextind(itr.string, mat.offset)
                else
                    offset = mat.offset
                end
            else
                offset = mat.offset + ncodeunits(mat.match)
            end
            return (mat, (offset, isempty(mat.match)))
        end
    end
    nothing
end

Base.eachmatch(re::Regex, str::DenseStringViewAndSub; overlap = false) =
    RegexMatchIterator(re, str, overlap)

# copied from julia/base/pcre.jl:
function PCRE.exec(re, subject::DenseStringViewAndSub, offset, options, match_data)
    rc = ccall((:pcre2_match_8, PCRE.PCRE_LIB), Cint,
                (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Csize_t, UInt32, Ptr{Cvoid}, Ptr{Cvoid}),
                re, subject, ncodeunits(subject), offset, options, match_data, PCRE.get_local_match_context())
    # rc == -1 means no match, -2 means partial match.
    rc < -2 && error("PCRE.exec error: $(PCRE.err_message(rc))")
    return rc >= 0
end

#####################################################################
# need to duplicate this code from Base because of julia#48617:
"""
    SVRegexMatch <: AbstractMatch

This type is identical to `RegexMatch` (in Julia `Base`) except that the
`match` is a `SubString` of a `StringView` instead of a `String`.

A type representing a single match to a `Regex` found in a string.
Typically created from the [`match`](@ref) function.

* The `match` field stores the substring of the entire matched string.
* The `captures` field stores the substrings for each capture group, indexed by number.
  To index by capture group name, the entire match object should be indexed instead,
  as shown in the examples.
* The location of the start of the match is stored in the `offset` field.
* The `offsets` field stores the locations of the start of each capture group,
  with 0 denoting a group that was not captured.

This type can be used as an iterator over the capture groups of the `Regex`,
yielding the substrings captured in each group.
Because of this, the captures of a match can be destructured.
If a group was not captured, `nothing` will be yielded instead of a substring.
"""
struct SVRegexMatch{T<:DenseStringView} <: AbstractMatch
    match::SubString{T}
    captures::Vector{Union{Nothing,SubString{T}}}
    offset::Int
    offsets::Vector{Int}
    regex::Regex
end
SVRegexMatch(match::SubString{T}, captures, offset, offsets, regex) where {T<:DenseStringViewAndSub} =
    SVRegexMatch{T}(match, captures, offset, offsets, regex)

function Base.keys(m::SVRegexMatch)
    idx_to_capture_name = PCRE.capture_names(m.regex.regex)
    return map(eachindex(m.captures)) do i
        # If the capture group is named, return it's name, else return it's index
        get(idx_to_capture_name, i, i)
    end
end

function Base.show(io::IO, m::SVRegexMatch)
    print(io, "SVRegexMatch(")
    show(io, m.match)
    capture_keys = keys(m)
    if !isempty(capture_keys)
        print(io, ", ")
        for (i, capture_name) in enumerate(capture_keys)
            print(io, capture_name, "=")
            show(io, m.captures[i])
            if i < length(m)
                print(io, ", ")
            end
        end
    end
    print(io, ")")
end

# Capture group extraction
Base.getindex(m::SVRegexMatch, idx::Integer) = m.captures[idx]
function Base.getindex(m::SVRegexMatch, name::Union{AbstractString,Symbol})
    idx = PCRE.substring_number_from_name(m.regex.regex, name)
    idx <= 0 && error("no capture group named $name found in regex")
    m[idx]
end

Base.haskey(m::SVRegexMatch, idx::Integer) = idx in eachindex(m.captures)
function Base.haskey(m::SVRegexMatch, name::Union{AbstractString,Symbol})
    idx = PCRE.substring_number_from_name(m.regex.regex, name)
    return idx > 0
end

Base.iterate(m::SVRegexMatch, args...) = iterate(m.captures, args...)
Base.length(m::SVRegexMatch) = length(m.captures)
Base.eltype(m::SVRegexMatch) = eltype(m.captures)