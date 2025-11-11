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
    _vn(expr, Iden)
end
function _vn(sym::Symbol, inner)
    return VN{sym,inner}()
end
function _vn(expr::Expr, inner)
    next_inner = if expr.head == :(.)
        # expr.args[2] isa QuoteNode, so we get the symbol with `value` 
        Prop{expr.args[2].value,inner}
    elseif expr.head == :ref
        # todo (or to-never-do): can't handle non-integer indices
        Indx{tuple(expr.args[2:end]...),inner}
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


end # module EnamRav
