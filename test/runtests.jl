using StringViews, Test

b = Vector{UInt8}("foobar")
s = StringView(b)
abc = StringView(0x61:0x63)
invalid = StringView([0x8b, 0x52, 0x9b, 0x8d])

@testset "Construction/conversion" begin
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

    @test cmp("foobar","bar") == cmp(s,"bar") == -cmp("bar",s) == cmp(s,StringView("bar"))
    @test s == StringView("foobar") == "foobar" == s == "foobar" != StringView("bar")
    @test cmp(abc, "bar") == cmp("abc","bar")

    @test Base.typemin(s) isa StringView{Vector{UInt8}}
    @test Base.typemin(s) == ""

    @test isascii(s)
    @test !isascii(StringView("fööbār"))

    @test Base.print_to_string(s) == "foobar"
    @test Base.print_to_string(abc) == "abc"

    @test isvalid(s)
    @test isvalid(abc)
    @test !isvalid(invalid)
    @test !invoke(isvalid, Tuple{StringView}, invalid)
end

@testset "regular expressions" begin
    @test [m.match for m in collect(eachmatch(r"[aeiou]+", s))] == ["oo", "a"]
end
