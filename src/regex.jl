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

function Base.match(re::Regex, str::DenseStringViewAndSub, idx::Integer, add_opts::UInt32=UInt32(0))
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
    cap = Union{Nothing,SubString{String}}[unsafe_load(p,2i+1) == PCRE.UNSET ? nothing :
                                           SubString(str, unsafe_load(p,2i+1)+1,
                                           prevind(str, unsafe_load(p,2i+2)+1)) for i=1:n]
    off = Int[ unsafe_load(p,2i+1)+1 for i=1:n ]
    result = RegexMatch(mat, cap, unsafe_load(p,1)+1, off, re)
    PCRE.free_match_data(data)
    return result
end

Base.findnext(re::Regex, str::DenseStringViewAndSub, idx::Integer) = _findnext_re(re, str, idx, C_NULL)

function _findnext_re(re::Regex, str::DenseStringViewAndSub, idx::Integer, match_data::Ptr{Cvoid})
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
Base.compile(itr::RegexMatchIterator) = (compile(itr.regex); itr)
Base.eltype(::Type{<:RegexMatchIterator}) = RegexMatch
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
    rc < -2 && error("PCRE.exec error: $(err_message(rc))")
    return rc >= 0
end
