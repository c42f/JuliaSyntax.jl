# Experimental port of some parts of Julia's code lowering (ie, the symbolic
# non-type-related compiler passes)

TODO(msg) = throw(ErrorException("Lowering TODO: $msg"))
TODO(ex, msg) = throw(LoweringError(ex, "Lowering TODO: $msg"))

#-------------------------------------------------------------------------------
NodeId = Int

"""
Directed graph with arbitrary attributes on nodes. Used here for representing
one or several syntax trees.
"""
struct SyntaxGraph
    edge_ranges::Vector{UnitRange{Int}}
    edges::Vector{NodeId}
    attributes::Dict{Symbol,Any}
end

SyntaxGraph() = SyntaxGraph(Vector{UnitRange{Int}}(), Vector{NodeId}(), Dict{Symbol,Any}())

function Base.show(io::IO, ::MIME"text/plain", graph::SyntaxGraph)
    print(io, SyntaxGraph,
          " with $(length(graph.edge_ranges)) vertices, $(length(graph.edges)) edges, and attributes:\n")
    show(io, MIME("text/plain"), graph.attributes)
end

function ensure_attributes!(graph::SyntaxGraph; kws...)
    for (k,v) in pairs(kws)
        @assert k isa Symbol
        @assert v isa Type
        if haskey(graph.attributes, k)
            v0 = valtype(graph.attributes[k])
            v == v0 || throw(ErrorException("Attribute type mismatch $v != $v0"))
        else
            graph.attributes[k] = Dict{NodeId,v}()
        end
    end
end

function newnode!(graph::SyntaxGraph)
    push!(graph.edge_ranges, 0:-1) # Invalid range start => leaf node
    return length(graph.edge_ranges)
end

function setchildren!(graph::SyntaxGraph, id, children::NodeId...)
    setchildren!(graph, id, children)
end

function setchildren!(graph::SyntaxGraph, id, children)
    n = length(graph.edges)
    graph.edge_ranges[id] = n+1:(n+length(children))
    # TODO: Reuse existing edges if possible
    append!(graph.edges, children)
end

function haschildren(graph::SyntaxGraph, id)
    first(graph.edge_ranges[id]) > 0
end

function numchildren(graph::SyntaxGraph, id)
    length(graph.edge_ranges[id])
end

function children(graph::SyntaxGraph, id)
    @view graph.edges[graph.edge_ranges[id]]
end

function child(graph::SyntaxGraph, id::NodeId, i::Integer)
    graph.edges[graph.edge_ranges[id][i]]
end

# FIXME: Probably terribly non-inferrable?
function setattr!(graph::SyntaxGraph, id; attrs...)
    for (k,v) in pairs(attrs)
        graph.attributes[k][id] = v
    end
end

function Base.getproperty(graph::SyntaxGraph, name::Symbol)
    # FIXME: Remove access to internals
    name === :edge_ranges && return getfield(graph, :edge_ranges)
    name === :edges       && return getfield(graph, :edges)
    name === :attributes  && return getfield(graph, :attributes)
    return getfield(graph, :attributes)[name]
end

function Base.get(graph::SyntaxGraph, name::Symbol, default)
    get(getfield(graph, :attributes), name, default)
end

function _convert_nodes(graph::SyntaxGraph, node::SyntaxNode)
    id = newnode!(graph)
    graph.head[id] = head(node)
    # FIXME: Decide on API here which isn't terribly inefficient
    graph.source_pos[id] = node.position
    # setattr!(graph, id, source_pos=node.position)
    if !isnothing(node.val)
        v = node.val
        if v isa Symbol
            v = string(v)
        end
        setattr!(graph, id, value=v)
    end
    # FIXME: remove `isnothing()` check if reverting Unions in SyntaxData
    let r = node.raw
        !isnothing(r) && (setattr!(graph, id, green_tree=r))
    end
    let s = node.source
        !isnothing(s) && (setattr!(graph, id, source=s))
    end
    if haschildren(node)
        cs = map(children(node)) do n
            _convert_nodes(graph, n)
        end
        setchildren!(graph, id, cs)
    end
    return id
end

struct SyntaxTree
    graph::SyntaxGraph
    id::NodeId
end

function Base.getproperty(tree::SyntaxTree, name::Symbol)
    # FIXME: Remove access to internals
    name === :graph && return getfield(tree, :graph)
    name === :id  && return getfield(tree, :id)
    id = getfield(tree, :id)
    return get(getproperty(getfield(tree, :graph), name), id) do
        error("Property `$name[$id]` not found")
    end
end

function Base.get(tree::SyntaxTree, name::Symbol, default)
    attr = get(getfield(tree, :graph), name, nothing)
    return isnothing(attr) ? default :
           get(attr, getfield(tree, :id), default)
end

function haschildren(tree::SyntaxTree)
    haschildren(tree.graph, tree.id)
end

function numchildren(tree::SyntaxTree)
    numchildren(tree.graph, tree.id)
end

function children(tree::SyntaxTree)
    (SyntaxTree(tree.graph, c) for c in children(tree.graph, tree.id))
end

function child(tree::SyntaxTree, i::Integer)
    SyntaxTree(tree.graph, child(tree.graph, tree.id, i))
end

function Base.getindex(tree::SyntaxTree, i::Integer)
    child(tree, i)
end

function Base.getindex(tree::SyntaxTree, r::UnitRange)
    (child(tree, i) for i in r)
end

Base.firstindex(tree::SyntaxTree) = 1
Base.lastindex(tree::SyntaxTree) = numchildren(tree)

function filename(tree::SyntaxTree)
    return filename(tree.source)
end

function hasattr(tree::SyntaxTree, name::Symbol)
    attr = get(tree.graph.attributes, name, nothing)
    return !isnothing(attr) && haskey(attr, tree.id)
end

function attrnames(tree::SyntaxTree)
    attrs = tree.graph.attributes
    [name for (name, value) in attrs if haskey(value, tree.id)]
end

source_location(::Type{LineNumberNode}, tree::SyntaxTree) = source_location(LineNumberNode, tree.source, tree.source_pos)
source_location(tree::SyntaxTree) = source_location(tree.source, tree.source_pos)
first_byte(tree::SyntaxTree) = tree.source_pos
last_byte(tree::SyntaxTree) = tree.source_pos + span(tree.green_tree) - 1

function head(tree::SyntaxTree)
    tree.head
end

function SyntaxTree(graph::SyntaxGraph, node::SyntaxNode)
    ensure_attributes!(graph, head=SyntaxHead, green_tree=GreenNode,
                       source_pos=Int, source=SourceFile, value=Any)
    id = _convert_nodes(graph, node)
    return SyntaxTree(graph, id)
end

function SyntaxTree(node::SyntaxNode)
    return SyntaxTree(SyntaxGraph(), node)
end

attrsummary(name, value) = string(name)
attrsummary(name, value::Number) = "$name=$value"

function _value_string(ex)
    val = get(ex, :value, nothing)
    k = kind(ex)
    nodestr = k == K"Identifier" ? val :
              k == K"SSALabel" ? "#SSA-$(ex.var_id)" :
              k == K"core" ? "core.$(ex.value)" :
              repr(val)
end

function _show_syntax_tree(io, current_filename, node, indent, show_byte_offsets)
    if hasattr(node, :source)
        fname = filename(node)
        line, col = source_location(node)
        posstr = "$(lpad(line, 4)):$(rpad(col,3))"
        if show_byte_offsets
            posstr *= "│$(lpad(first_byte(node),6)):$(rpad(last_byte(node),6))"
        end
    else
        fname = nothing
        posstr = "        "
        if show_byte_offsets
            posstr *= "│             "
        end
    end
    val = get(node, :value, nothing)
    nodestr = haschildren(node) ? "[$(untokenize(head(node)))]" : _value_string(node)

    treestr = string(indent, nodestr)

    std_attrs = Set([:value,:source_pos,:head,:source,:green_tree])
    attrstr = join([attrsummary(n, getproperty(node, n)) for n in attrnames(node) if n ∉ std_attrs], ",")
    if !isempty(attrstr)
        treestr = string(rpad(treestr, 40), "│ $attrstr")
    end

    # Add filename if it's changed from the previous node
    if fname != current_filename[] && !isnothing(fname)
        #println(io, "# ", fname)
        treestr = string(rpad(treestr, 80), "│$fname")
        current_filename[] = fname
    end
    println(io, posstr, "│", treestr)
    if haschildren(node)
        new_indent = indent*"  "
        for n in children(node)
            _show_syntax_tree(io, current_filename, n, new_indent, show_byte_offsets)
        end
    end
end

function Base.show(io::IO, ::MIME"text/plain", tree::SyntaxTree; show_byte_offsets=false)
    println(io, "line:col│ tree                                   │ attributes                            | file_name")
    _show_syntax_tree(io, Ref{Union{Nothing,String}}(nothing), tree, "", show_byte_offsets)
end

function _show_syntax_tree_sexpr(io, ex)
    if !haschildren(ex)
        if is_error(ex)
            print(io, "(", untokenize(head(ex)), ")")
        else
            print(io, _value_string(ex))
        end
    else
        print(io, "(", untokenize(head(ex)))
        first = true
        for n in children(ex)
            print(io, ' ')
            _show_syntax_tree_sexpr(io, n)
            first = false
        end
        print(io, ')')
    end
end

function Base.show(io::IO, ::MIME"text/x.sexpression", node::SyntaxTree)
    _show_syntax_tree_sexpr(io, node)
end

function Base.show(io::IO, node::SyntaxTree)
    _show_syntax_tree_sexpr(io, node)
end


#-------------------------------------------------------------------------------
# Lowering types

"""
Unique symbolic identity for a variable within a `LoweringContext`
"""
const VarId = Int

"""
Metadata about a variable name - whether it's a local, etc
"""
struct VarInfo
    name::String
    islocal::Bool          # Local variable (if unset, variable is global)
    is_single_assign::Bool # Single assignment
    # isarg::Bool # Is a function argument ??
    # etc
end

struct SSAVar
    id::VarId
end

# Mirror of flisp scope info structure
# struct ScopeInfo
#     lambda_vars::Union{LambdaLocals,LambdaVars}
#     parent::Union{Nothing,ScopeInfo}
#     args::Set{Symbol}
#     locals::Set{Symbol}
#     globals::Set{Symbol}
#     static_params::Set{Symbol}
#     renames::Dict{Symbol,Symbol}
#     implicit_globals::Set{Symbol}
#     warn_vars::Set{Symbol}
#     is_soft::Bool
#     is_hard::Bool
#     table::Dict{Symbol,Any}
# end

struct ScopeInfo
    locals::Dict{Symbol,VarId}
    is_soft::Bool
    is_hard::Bool
end

ScopeInfo(; is_soft=false, is_hard=false) = ScopeInfo(Dict{Symbol,VarId}(), is_soft, is_hard)

struct LoweringContext
    graph::SyntaxGraph
    next_var_id::Ref{VarId}
    globals::Dict{Symbol,VarId}
    scope_stack::Vector{ScopeInfo}  # Stack of name=>id mappings for each scope, innermost scope last.
    var_info::Dict{VarId,VarInfo}  # id=>info mapping containing information about all variables
end

function LoweringContext()
    LoweringContext(SyntaxGraph(),
                    Ref{VarId}(1),
                    Dict{Symbol,VarId}(),
                    Vector{ScopeInfo}(),
                    Dict{VarId,VarInfo}())
end

#-------------------------------------------------------------------------------
struct LoweringError <: Exception
    ex
    msg
end

function Base.showerror(io::IO, exc::LoweringError)
    print(io, "LoweringError")
    # ctx = exc.context
    # if !isnothing(ctx)
    #     print(io, " while expanding ", ctx.macroname,
    #           " in module ", ctx.mod)
    # end
    print(io, ":\n")
    d = Diagnostic(first_byte(exc.ex), last_byte(exc.ex), error=exc.msg)
    show_diagnostic(io, d, exc.ex.source)
end

function chk_code(ex, cond)
    cond_str = string(cond)
    quote
        ex = $(esc(ex))
        @assert ex isa SyntaxTree
        try
            ok = $(esc(cond))
            if !ok
                throw(LoweringError(ex, "Expected `$($cond_str)`"))
            end
        catch
            throw(LoweringError(ex, "Structure error evaluating `$($cond_str)`"))
        end
    end
end

macro chk(cond)
    ex = cond
    while true
        if ex isa Symbol
            break
        elseif ex.head == :call
            ex = ex.args[2]
        elseif ex.head == :ref
            ex = ex.args[1]
        elseif ex.head == :.
            ex = ex.args[1]
        elseif ex.head in (:(==), :(in), :<, :>)
            ex = ex.args[1]
        else
            error("Can't analyze $cond")
        end
    end
    chk_code(ex, cond)
end

macro chk(ex, cond)
    chk_code(ex, cond)
end

#-------------------------------------------------------------------------------

# pass 1: syntax desugaring

function is_quoted(ex)
    kind(ex) in KSet"quote top core globalref outerref break inert
                     meta inbounds inline noinline loopinfo"
end

function expand_condition(ctx, ex)
    if head(ex) == K"block" || head(ex) == K"||" || head(ex) == K"&&"
        # || and && get special lowering so that they compile directly to jumps
        # rather than first computing a bool and then jumping.
        error("TODO expand_condition")
    end
    expand_forms(ctx, ex)
end

function expand_forms(ctx, ex)
    ensure_attributes!(ctx.graph, scope=ScopeInfo)
    ensure_attributes!(ctx.graph, hard_scope=Bool)
    ensure_attributes!(ctx.graph, var_id=VarId)
    SyntaxTree(ctx.graph, _expand_forms(ctx, ex))
end

_node_id(ex::NodeId) = ex
_node_id(ex::SyntaxTree) = ex.id

_node_ids() = ()
_node_ids(c, cs...) = (_node_id(c), _node_ids(cs...)...)

function makenode(ctx::LoweringContext, srcref, head, children...; attrs...)
    makenode(ctx.graph, srcref, head, _node_ids(children...)...; attrs...)
end

function makenode(graph::SyntaxGraph, srcref, head, children...; attrs...)
    id = newnode!(graph)
    if kind(head) in (K"Identifier", K"core") || is_literal(head)
        @assert length(children) == 0
    else
        setchildren!(graph, id, children)
    end
    setattr!(graph, id; head=head, attrs...)
    setattr!(graph, id;
             source=srcref.source,
             green_tree=srcref.green_tree,
             source_pos=srcref.source_pos)
    return id
end

function ssavar(ctx::LoweringContext, srcref)
    id = makenode(ctx, srcref, K"SSALabel", var_id=ctx.next_var_id[])
    ctx.next_var_id[] += 1
    return id
end

function assign_tmp(ctx::LoweringContext, ex)
    tmp = ssavar(ctx, ex)
    tmpdef = makenode(ctx, ex, K"=", tmp, ex)
    tmp, tmpdef
end

function expand_assignment(ctx, ex)
end

function is_sym_decl(x)
    k = kind(x)
    k == K"Identifier" || k == K"::"
end

function decl_var(ex)
    kind(ex) == K"::" ? ex[1] : ex
end

function expand_let(ctx, ex)
    is_hard_scope = get(ex, :hard_scope, true)
    blk = expand_forms(ctx, ex[2])
    for binding in Iterators.reverse(children(ex[1]))
        kb = kind(binding)
        if is_sym_decl(kb)
            blk = makenode(ctx, ex, K"block",
                makenode(ctx, ex, K"local", binding; sr...),
                blk;
                sr...,
                scope=ScopeInfo(is_hard=is_hard_scope)
            )
        elseif kb == K"=" && numchildren(binding) == 2
            lhs = binding[1]
            rhs = binding[2]
            if is_sym_decl(lhs)
                tmp, tmpdef = assign_tmp(ctx, rhs)
                blk = makenode(ctx, binding, K"block",
                    tmpdef,
                    makenode(ctx, ex, K"block",
                        makenode(ctx, lhs, K"local_def", lhs), # TODO: Use K"local" with attr?
                        makenode(ctx, rhs, K"=", decl_var(lhs), tmp),
                        blk;
                        scope=ScopeInfo(is_hard=is_hard_scope)
                    )
                )
            else
                TODO("Functions and multiple assignment")
            end
        else
            throw(LoweringError(binding, "Invalid binding in let"))
            continue
        end
    end
    return blk
end

# FIXME: The problem of "what is an identifier" pervades lowering ... we have
# various things which seem like identifiers:
#
# * Identifier (symbol)
# * K"var" nodes
# * Operator kinds
# * Underscore placeholders
#
# Can we avoid having the logic of "what is an identifier" repeated by dealing
# with these during desugaring
# * Attach an identifier attribute to nodes. If they're an identifier they get this
# * Replace operator kinds by K"Identifier" in parsing?
# * Replace operator kinds by K"Identifier" in desugaring?
function identifier_name(ex)
    kind(ex) == K"var" ? ex[1] : ex
end

function analyze_function_arg(full_ex)
    name = nothing
    type = nothing
    default = nothing
    is_slurp = false
    is_nospecialize = false
    ex = full_ex
    while true
        k = kind(ex)
        if k == K"Identifier" || k == K"tuple"
            name = ex
            break
        elseif k == K"::"
            @chk numchildren(ex) in (1,2)
            if numchildren(ex) == 1
                type = ex[1]
            else
                name = ex[1]
                type = ex[2]
            end
            break
        elseif k == K"..."
            @chk full_ex !is_slurp
            @chk numchildren(ex) == 1
            is_slurp = true
            ex = ex[1]
        elseif k == K"meta"
            @chk ex[1].value == "nospecialize"
            is_nospecialize = true
            ex = ex[2]
        elseif k == K"="
            @chk full_ex isnothing(default) && !is_slurp
            default = ex[2]
            ex = ex[1]
        else
            throw(LoweringError(ex, "Invalid function argument"))
        end
    end
    return (name=name,
            type=type,
            default=default,
            is_slurp=is_slurp,
            is_nospecialize=is_nospecialize)
end

core_ref(ctx, ex, name) = makenode(ctx, ex, K"core", value=name)
Any_type(ctx, ex) = core_ref(ctx, ex, "Any")
svec_type(ctx, ex) = core_ref(ctx, ex, "svec")
nothing_(ctx,ex) = core_ref(ctx, ex, "nothing")

function expand_function_def(ctx, ex)
    name = ex[1]
    if kind(name) == K"where"
        TODO("where handling")
    end
    if kind(name) == K"::"
        rettype = name[2]
        name = name[1]
    else
        rettype = Any_type(ctx, name)
    end
    if numchildren(ex) == 2 && is_identifier(name) # TODO: Or name as globalref
        if !is_valid_name(name)
            throw(LoweringError(name, "Invalid function name"))
        end
        return makenode(ctx, ex, K"method", identifier_name(name))
    elseif kind(name) == K"call"
        callex = name
        body = ex[2]
        # TODO
        # static params
        # nospecialize
        # argument destructuring
        # dotop names
        # overlays

        # Add self argument where necessary
        args = name[2:end]
        name = name[1]
        if kind(name) == K"::"
            if numchildren(name) == 1
                farg = makenode(ctx, name, K"::",
                                makenode(ctx, name, K"Identifier", value="#self#"),
                                name[1])
            else
                TODO("Fixme type")
                farg = name
            end
            function_name = nothing_(ctx, ex)
        else
            farg = makenode(ctx, name, K"::",
                            makenode(ctx, name, K"Identifier", value="#self#"),
                            makenode(ctx, name, K"call",
                                     makenode(ctx, name, K"core", value="Typeof"),
                                     name))
            function_name = name
        end

        # preamble is arbitrary code which computes
        # svec(types, sparms, location)

        types = []
        for (i,arg) in enumerate(args)
            info = analyze_function_arg(arg)
            type = !isnothing(info.type) ? info.type : Any_type(ctx, name)
            @assert !info.is_nospecialize # TODO
            @assert !isnothing(info.name) && kind(info.name) == K"Identifier" # TODO
            if info.is_slurp
                if i != length(args)
                    throw(LoweringError(arg, "`...` may only be used for the last function argument"))
                end
                type = makenode(K"curly", core_ref(ctx, arg, "Vararg"), arg)
            end
            push!(types, type)
        end

        preamble = makenode(ctx, ex, K"call",
                            svec_type(ctx, callex),
                            makenode(ctx, callex, K"call",
                                     svec_type(ctx, name),
                                     types...),
                            makenode(ctx, callex, K"Value", value=source_location(LineNumberNode, callex))
                           )
        return makenode(ctx, ex, K"method",
                        function_name,
                        preamble,
                        body)
    elseif kind(name) == K"tuple"
        TODO(name, "Anon function lowering")
    else
        throw(LoweringError(name, "Bad function definition"))
    end
end

function _expand_forms(ctx, ex)
    k = kind(ex)
    if k == K"function"
        expand_function_def(ctx, ex)
    elseif k == K"let"
        return expand_let(ctx, ex)
    elseif is_operator(k) && !haschildren(ex)
        return makenode(ctx, ex, K"Identifier", value=ex.value)
    elseif k == K"char" || k == K"var"
        @assert numchildren(ex) == 1
        return ex[1]
    elseif k == K"string" && numchildren(ex) == 1 && kind(ex[1]) == K"String"
        return ex[1]
    elseif !haschildren(ex)
        return ex
    else
        if k == K"="
            @chk numchildren(ex) == 2
            if kind(ex[1]) != K"Identifier"
                TODO(ex, "destructuring assignment")
            end
        end
        # FIXME: What to do about the ids vs SyntaxTree?
        makenode(ctx, ex, head(ex), [_expand_forms(ctx,e) for e in children(ex)]...)
    end
end

#-------------------------------------------------------------------------------
# Pass 2: analyze scopes (passes 2/3 in flisp code)
#
# This pass analyzes the names (variables/constants etc) used in scopes
#
# This pass records information about variables used by closure conversion.
# finds which variables are assigned or captured, and records variable
# type declarations.
#
# This info is recorded by setting the second argument of `lambda` expressions
# in-place to
#   (var-info-lst captured-var-infos ssavalues static_params)
# where var-info-lst is a list of var-info records

function is_underscore(ex)
    k = kind(ex)
    return (k == K"Identifier" && valueof(ex) == :_) ||
           (k == K"var" && valueof(ex[1]) == :_)
end

function identifier_name_str(ex)
    identifier_name(ex).value
end

function is_valid_name(ex)
    n = identifier_name_str(ex)
    n !== "ccall" && n !== "cglobal"
end

function _schedule_traverse(stack, e)
    push!(stack, e)
    return nothing
end
function _schedule_traverse(stack, es::Union{Tuple,Vector,Base.Generator})
    append!(stack, es)
    return nothing
end

function traverse_ast(f, ex)
    todo = [ex]
    while !isempty(todo)
        e1 = pop!(todo)
        f(e1, e->_schedule_traverse(todo, e))
    end
end

function find_in_ast(f, ex)
    todo = [ex]
    while !isempty(todo)
        e1 = pop!(todo)
        res = f(e1, e->_schedule_traverse(todo, e))
        if !isnothing(res)
            return res
        end
    end
    return nothing
end

# NB: This only really works after expand_forms has already processed assignments.
function find_assigned_vars(ex)
    vars = Vector{typeof(ex)}()
    traverse_ast(ex) do e, traverse
        k = kind(e)
        if !haschildren(e) || is_quoted(k) || k in KSet"lambda scope_block module toplevel"
            return
        elseif k == K"method"
            TODO(e, "method")
            return nothing
        elseif k == K"="
            v = decl_var(e[1])
            if !(kind(v) in KSet"SSALabel globalref outerref" || is_underscore(e))
                push!(vars, v)
            end
            traverse(e[2])
        else
            traverse(children(e))
        end
    end
    var_names = String[v.value for v in vars]
    return unique(var_names)
end

function find_decls(decl_kind, ex)
    vars = Vector{typeof(ex)}()
    traverse_ast(ex) do e, traverse
        k = kind(e)
        if !haschildren(e) || is_quoted(k) || k in KSet"lambda scope_block module toplevel"
            return
        elseif k == decl_kind
            if !is_underscore(e[1])
                push!(vars, decl_var(e[1]))
            end
        else
            traverse(children(e))
        end
    end
    var_names = String[v.value for v in vars]
    return unique(var_names)
end

# Determine whether decl_kind is in the scope of `ex`
#
# flisp: find-scope-decl
function has_scope_decl(decl_kind, ex)
    find_in_ast(ex) do e, traverse
        k = kind(e)
        if !haschildren(e) || is_quoted(k) || k in KSet"lambda scope_block module toplevel"
            return
        elseif k == decl_kind
            return e
        else
            traverse(children(ex))
        end
    end
end

struct LambdaLocals
    # For resolve-scopes pass
    locals::Set{Symbol}
end

# TODO:
# Incorporate hygenic-scope here so we always have a parent scope when
# processing variables

# Steps
# 1. Deal with implicit locals and globals only
# 2. Add local, global etc later

# struct LambdaVars
#     # For analyze-variables pass
#     # var_info_lst::Set{Tuple{Symbol,Symbol}} # ish?
#     # captured_var_infos ??
#     # ssalabels::Set{SSALabel}
#     # static_params::Set{Symbol}
# end

struct LambdaVars
    arg_vars::Set{VarId}
    body_vars::Set{VarId}
end

LambdaVars(args) = LambdaVars(Set{VarId}(), Set{VarId}())

function resolve_scopes(ctx, ex)
    thk_vars = LambdaVars()
    resolve_scopes(ctx, thk_vars, ex)
end

function resolve_scopes(ctx, lambda_vars, ex)
    k = kind(ex)
    if k == K"Identifier"
        # Look up identifier
        name = ex.value
        for s in Iterators.reverse(ctx.scope_stack)
        end
    elseif k == K"global"
        TODO("global")
    elseif k == K"local" || k == K"local_def"
        TODO("local") # Remove these
    # TODO
    # elseif require_existing_local
    # elseif locals # return Dict of locals
    # elseif islocal
    elseif k == K"lambda"
        vars = LambdaVars(ex[1])
        resolve_scopes(ctx, vars, ex[2])
    elseif hasattr(ex, :scope)
        # scope-block
    end
    # scope = get(ex, :scope, nothing)
    # if !isnothing(scope)
    # for e in children(ex)
    #     resolve_scopes(ctx, child_scope, e)
    # end
end

#-------------------------------------------------------------------------------
# Pass 3: closure conversion
#
# This pass lifts all inner functions to the top level by generating
# a type for them.
#
# For example `f(x) = y->(y+x)` is converted to
#
#     immutable yt{T}
#         x::T
#     end
#
#     (self::yt)(y) = y + self.x
#
#     f(x) = yt(x)

#-------------------------------------------------------------------------------
# Pass 4: Flatten to linear IR


