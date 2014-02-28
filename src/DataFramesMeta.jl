module DataFramesMeta

importall Base
importall DataFrames
using DataFrames

# Basics:
export @with, @ix, @where, @orderby, @transform, @by, @based_on, @select
export where, orderby, transform, select 


##############################################################################
##
## @with
##
##############################################################################

replace_syms(x, membernames) = x
function replace_syms(e::Expr, membernames)
    if e.head == :call && length(e.args) == 2 && e.args[1] == :^
        return e.args[2]
    elseif e.head == :.     # special case for :a.b
        return Expr(e.head, replace_syms(e.args[1], membernames),
                            typeof(e.args[2]) == Expr && e.args[2].head == :quote ? e.args[2] : replace_syms(e.args[2], membernames))
    elseif e.head != :quote
        return Expr(e.head, (isempty(e.args) ? e.args : map(x -> replace_syms(x, membernames), e.args))...)
    else
        if haskey(membernames, e.args[1])
            return membernames[e.args[1]]
        else
            a = gensym()
            membernames[e.args[1]] = a
            return a
        end
    end
end

function with_helper(d, body)
    membernames = Dict{Symbol, Symbol}()
    body = replace_syms(body, membernames)
    funargs = map(x -> :( getindex($d, $(Meta.quot(x))) ), collect(keys(membernames)))
    funname = gensym()
    return(:( function $funname($(collect(values(membernames))...)) $body end; $funname($(funargs...)) ))
end

macro with(d, body)
    esc(with_helper(d, body))
end


##############################################################################
##
## @withfirst - helper
##            - @withfirst( fun(df, :a) ) becomes @with(df, fund(df, :a))
##
##############################################################################

function withfirst_helper(e)
    quote
        let d = $(e.args[2]); 
            @with(d, $(e.args[1])(d, $(e.args[3:end]...)))
        end
    end
end

macro withfirst(e)
    esc(withfirst_helper(e))
end


##############################################################################
##
## @ix - row and row/col selector
##
##############################################################################

ix_helper(d, arg) = :( let d = $d; $d[@with($d, $arg),:]; end )
ix_helper(d, arg, moreargs...) = :( let d = $d; getindex(d, @with(d, $arg), $(moreargs...)); end )

macro ix(d, args...)
    esc(ix_helper(d, args...))
end


##############################################################################
##
## @where - select row subsets
##
##############################################################################

where(d::AbstractDataFrame, arg) = d[arg, :]
where(d::AbstractDataFrame, f::Function) = d[f(d), :]
where(g::GroupedDataFrame, f::Function) = (@show Bool[f(x) for x in g]; g[Bool[f(x) for x in g]])
where(g::GroupedDataFrame, f::Function) = g[Bool[f(x) for x in g]]

## macro where(d, arg)
##     esc(:( @withfirst where($d, $arg) ))
## end


where_helper(d, arg) = :( where($d, x -> @with(x, $arg)) )

macro where(d, arg)
    esc(where_helper(d, arg))
end


##############################################################################
##
## select - select columns
##
##############################################################################

select(d::AbstractDataFrame, arg) = d[:, arg]


##############################################################################
##
## @orderby
##
##############################################################################

function orderby(d::AbstractDataFrame, args...)
    D = typeof(d)(args...)
    d[sortperm(D), :]
end
orderby(d::AbstractDataFrame, f::Function) = d[sortperm(f(d)), :]
orderby(g::GroupedDataFrame, f::Function) = g[sortperm([f(x) for x in g])]

macro orderby(d, arg)
    esc(:( orderby($d, x -> @with(x, $arg)) ))
end


##############################################################################
##
## transform & @transform
##
##############################################################################

function transform(d::Union(AbstractDataFrame, Associative); kwargs...)
    result = copy(d)
    for (k, v) in kwargs
        result[k] = v
    end
    return result
end

macro transform(x, args...)
    esc(:(let x = $x; @with(x, transform(x, $(args...))); end))
end


##############################################################################
##
## @based_on - summarize a grouping operation
##
##############################################################################

macro based_on(x, args...)
    esc(:( DataFrames.based_on($x, _DF -> @with(_DF, DataFrame($(args...)))) ))
end


##############################################################################
##
## @by - grouping
##
##############################################################################

macro by(x, what, args...)
    esc(:( by($x, $what, _DF -> @with(_DF, DataFrame($(args...)))) ))
end


##############################################################################
##
## @select - select and transform columns
##
##############################################################################

expandargs(x) = x

function expandargs(e::Expr) 
    if e.head == :quote && length(e.args) == 1
        return Expr(:kw, e.args[1], Expr(:quote, e.args[1]))
    else
        return e
    end
end

function expandargs(e::Tuple)
    res = [e...]
    for i in 1:length(res)
        res[i] = expandargs(e[i])
    end
    return res
end

function select(d::Union(AbstractDataFrame, Associative); kwargs...)
    result = typeof(d)()
    for (k, v) in kwargs
        result[k] = v
    end
    return result
end

macro select(x, args...)
    esc(:(let x = $x; @with(x, select(x, $(expandargs(args)...))); end))
end


##############################################################################
##
## Extras for GroupedDataFrames
##
##############################################################################

combnranges(starts, ends) = [[starts[i]:ends[i] for i in 1:length(starts)]...]

DataFrame(g::GroupedDataFrame) = g.parent[g.idx[combnranges(g.starts, g.ends)], :]

Base.getindex(gd::GroupedDataFrame, I::AbstractArray{Int}) = GroupedDataFrame(gd.parent,
                                                                              gd.cols,
                                                                              gd.idx,
                                                                              gd.starts[I],
                                                                              gd.ends[I])

end # module
