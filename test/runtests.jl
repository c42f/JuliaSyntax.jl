using JuliaSyntax
using Test

using JuliaSyntax: SourceFile
using JuliaSyntax: RawSyntaxNode, SyntaxNode, raw_flags, TRIVIA_FLAG, INFIX_FLAG
using JuliaSyntax: Kind, @K_str, children, child, setchild!
using JuliaSyntax: highlight
using JuliaSyntax: ParseStream, bump!, peek, begin_node, end_node

# Shortcuts for defining raw syntax nodes

# Trivia nodes
T(k, s) = RawSyntaxNode(k, s, raw_flags(trivia=true))
# Non-trivia nodes
N(k, s) = RawSyntaxNode(k, s)
N(k, args::RawSyntaxNode...) = RawSyntaxNode(k, args...)
# Non-trivia, infix form
NI(k, args::RawSyntaxNode...) = RawSyntaxNode(k, raw_flags(infix=true), args...)


include("syntax_trees.jl")
include("syntax_interpolation.jl")
include("parse_stream.jl")

