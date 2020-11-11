using StringViews, Test

b = Vector{UInt8}("foobar")
s = StringView(b)
ss = SubString(s, 2, 5) # "ooba"
abc = StringView(0x61:0x63)
invalid = StringView([0x8b, 0x52, 0x9b, 0x8d])
su = StringView("föôẞαr")

@testset "construction/conversion" begin
    @test StringView(s) === s
    @test Vector{UInt8}(s) === Array{UInt8}(s) === codeunits(s) === b
    @test Vector{UInt8}(StringView(@view b[1:3])) == b[1:3]
    @test codeunits(String(s)) == s.data
    @test Vector{UInt8}(abc) == collect(0x61:0x63)
    @test Symbol(s) == :foobar
    @test Symbol(abc) == :abc

    @test StringView("foo") isa StringView{Base.CodeUnits{UInt8,String}}

    @test s isa StringViews.DenseStringView
    @test StringView(@view b[1:3]) isa StringViews.DenseStringView
    @test StringView("foo") isa StringViews.DenseStringView
    @test StringView(@view codeunits("foobar")[1:3]) isa StringViews.DenseStringView

    @test pointer(s) == pointer(b) == Base.unsafe_convert(Ptr{UInt8}, s)
    @test Base.unsafe_convert(Ptr{Int8}, s) == Ptr{Int8}(pointer(s))
    @test pointer(s, 3) == pointer(b, 3)
    @test_throws MethodError pointer(abc)

    @test ncodeunits(s) == sizeof(s) == length(b)
    @test codeunit(s) == UInt8
    @test codeunit(s,3) == b[3]

    @test Base.print_to_string(s) == "foobar"
    @test Base.print_to_string(abc) == "abc"
end

@testset "substrings" begin
    @test Vector{UInt8}(ss) == Array{UInt8}(ss) == codeunits(ss) == b[2:5]
    @test codeunits(ss) isa Base.FastContiguousSubArray
    @test Symbol(ss) == :ooba

    @test pointer(ss) == pointer(b) + 1 == Base.unsafe_convert(Ptr{UInt8}, ss)
    @test ncodeunits(ss) == sizeof(ss) == length(b)-2
    @test codeunit(ss) == UInt8
    @test codeunit(ss,3) == b[4]

    @test Base.print_to_string(ss) == "ooba"

    @test cmp("foobar","bar") == cmp(ss,"bar") == -cmp("bar",ss) == cmp(ss,StringView("bar"))
    @test ss == StringView("ooba") == "ooba" == ss == "ooba"
    @test isvalid(ss)
end

@testset "iteration" begin
    for str in (s, ss, abc, invalid, su)
        sS = String(str)
        @test sS == str
        @test length(sS) == length(str)
        @test collect(sS) == collect(str) ==
              getindex.(sS, eachindex(sS)) == getindex.(str, eachindex(sS))
        @test collect(eachindex(sS)) == collect(eachindex(str))
        @test sS[1:end] == str[1:end]
        @test sS[nextind(sS,1):prevind(sS,end)] == str[nextind(str,1):prevind(str,end)]
    end
end

@testset "regular expressions" begin
    for str in (s,ss)
        @test [m.match for m in collect(eachmatch(r"[aeiou]+", str))] == ["oo", "a"]
        @test occursin(r"o+", str) && !occursin(r"z+", str)
        @test startswith(str, r"o+") == (str[1:2] == "oo")
        @test startswith(str, r"f+") == (str[1:2] == "fo")
        @test endswith(str, r"[aeiou]") == (str[end] == 'a')
        @test endswith(str, r"[q-z]") == (str[end] == 'r')
        @test findnext(r"o+", str, 4) === nothing
    end
    @test findnext(r"[aeiou]+", s, 1) == 2:3
    @test findnext(r"[aeiou]+", ss, 1) == 1:2
end

@testset "miscellaneous" begin
    @test cmp("foobar","bar") == cmp(s,"bar") == -cmp("bar",s) == cmp(s,StringView("bar"))
    @test s == StringView("foobar") == "foobar" == s == "foobar" != StringView("bar")
    @test cmp(abc, "bar") == cmp("abc","bar")

    @test Base.typemin(s) isa StringView{Vector{UInt8}}
    @test Base.typemin(s) == ""

    @test isascii(s)
    @test !isascii(StringView("fööbār"))

    @test isvalid(s)
    @test isvalid(abc)
    @test !isvalid(invalid)
    @test !invoke(isvalid, Tuple{StringView}, invalid)

    for str in (s, abc, invalid, ss)
        @test hash(str) == hash(String(str))
    end
end
