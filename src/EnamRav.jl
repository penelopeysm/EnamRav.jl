module EnamRav

using Test
using Chairmarks: @be

export @vn, VN, Lens, Iden, Prop, Indx, VNM, demo

# https://github.com/TuringLang/AbstractPPL.jl/issues/127
# incidentally, i think this tree-like structure is much easier to deal with
# than Accessors. notice that there's no need for ComposedFunction or
# normalisation of optics etc with this.
abstract type Lens end
struct Iden <: Lens end
struct Prop{sym,T<:Lens} <: Lens end   # sym should be a symbol
struct Indx{inds,T<:Lens} <: Lens end  # inds is a tuple of indices
# we can implement an Accessors-like API as well, it's not hard, just a faff

struct VN{sym,L<:Lens} end
macro vn(expr)
    esc(_vn(expr, :Iden))
end
function _vn(sym::Symbol, inner_expr)
    return :($VN{$(QuoteNode(sym)),$inner_expr}())
end
function _vn(expr::Expr, inner_expr)
    next_inner = if expr.head == :(.)
        :(Prop{$(expr.args[2]),$inner_expr})
    elseif expr.head == :ref
        # todo (or to-never-do): can't handle non-integer indices
        :(Indx{tuple($(expr.args[2:end]...)),$inner_expr})
    else
        error("you will pay for this when the robots take over the world")
    end
    return _vn(expr.args[1], next_inner)
end

struct VNM{vns,N<:NamedTuple}
    nt::N
    # constructor is slow, but maybe that's alright? how often
    # are we constructing things? if we keep the constructor out
    # of performance-sensitive loops i think it's OK?
    function VNM(vns_to_vals::AbstractDict{<:VN,<:Any})
        vns = tuple(keys(vns_to_vals)...)
        n = NamedTuple(Symbol(:vn, i) => v for (i, v) in enumerate(values(vns_to_vals)))
        return new{vns,typeof(n)}(n)
    end
end

# unsure if `Base.@constprop :aggressive` makes a difference
# likewise unsure if `@inline` also makes a difference
Base.@constprop :aggressive @inline @generated function Base.getindex(vnm::VNM{vns}, t::T) where {vns,T<:VN}
    for (i, vn) in enumerate(vns)
        if typeof(vn) == T
            return :(vnm.nt[$i])
        end
    end
    throw(KeyError(t))
end
# the implementation of setindex!! would follow from the constructor

function demo()
    @testset "EnamRav" begin
        d = Dict(@vn(x) => 1.0, @vn(y[1]) => zeros(3), @vn(z.a) => "hello")
        vnm = VNM(d)
        @show vnm

        @testset "$k" for (k, v) in d
            println()
            println(" --------- getindex with $k ---------- ")
            @test vnm[k] == v
            @inferred vnm[k]
            display(code_typed(Base.getindex, (typeof(vnm), typeof(k))))
            display(@be vnm[k])
        end

        # missing key
        @test_throws KeyError vnm[@vn(nope)]

        # Also interesting:
        function f(d_or_vnm::T) where {T}
            return 1.0 + d_or_vnm[@vn(x)]
        end
        println()
        println()
        println(" ------- getindex in downstream code -------- ")
        display(code_typed(f, (typeof(d),)))
        println()
        println()
        display(code_typed(f, (typeof(vnm),)))
        println()
        println()
    end
end

"""
# The above design allows for completely type stable indexing
# into VNM, BUT this only holds true if the VN type is known.
# If the VN type depends on a variable (e.g. an index in a loop),
# then this will struggle. Here's a demo:

using EnamRav
N = 50
function make_dict(N)
    d = Dict{VN,Float64}()
    for i in 1:N
        d[@vn(x[i])] = 1.0
    end
    return d
end
# First time takes AGES! probably to do with the
# fact that every x[i] is a different type...
@time make_dict(N);
@time make_dict(N);

d = make_dict(N)
vnm = VNM(d)
function f(vnm)
    local sum = 0.0
    for i in 1:N
        sum += vnm[@vn(x[i])]
    end
    return sum
end
@time f(vnm)  # 99 ms first time
@time f(vnm)  # 88 µs subsequent times
# Here you can observe one of the problems of this data type:
# because `i` is part of the type, it cannot infer the type
# of `@vn(x[i])` inside the loop, and consequently it cannot
# infer the type of `vnm[@vn(x[i])]`, even though they are
# all Float64s.
@code_typed f(vnm)

# This is what it should be:
xs = fill(1.0, N)
@time sum(xs)  # 13 ms first time
@time sum(xs)  # 4 µs, 1 alloc

# Of course, the way to get around it is to do everything
# at the type level by unrolling the loop...
@generated function f2(vnm)
    expr = quote
        sum = 0.0
    end
    for i in 1:N
        push!(expr.args, :(vnm[@vn(x[i])]))
    end
    push!(expr.args, :(return sum))
end
@time f2(vnm); # 10 ms
@time f2(vnm); # 3 µs, 0 allocs

"""


end # module EnamRav
