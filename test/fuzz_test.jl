using JuliaSyntax
using JuliaSyntax: tokenize
import Logging
import Test

# Parser fuzz testing tools.

const all_tokens = [
    "#x\n"
    "#==#"
    " "
    "\t"
    "\n"
    "x"
    "@"
    ","
    ";"

    "baremodule"
    "begin"
    "break"
    "const"
    "continue"
    "do"
    "export"
    "for"
    "function"
    "global"
    "if"
    "import"
    "let"
    "local"
    "macro"
    "module"
    "quote"
    "return"
    "struct"
    "try"
    "using"
    "while"
    "catch"
    "finally"
    "else"
    "elseif"
    "end"
    "abstract"
    "as"
    "doc"
    "mutable"
    "outer"
    "primitive"
    "type"
    "var"

    "1"
    "0b1"
    "0x1"
    "0o1"
    "1.0"
    "1.0f0"
    "\"s\""
    "'c'"
    "`s`"
    "true"
    "false"

    "["
    "]"
    "{"
    "}"
    "("
    ")"
    "\""
    "\"\"\""
    "`"
    "```"

    "="
    "+="
    "-="   # Also used for "−="
    "−="
    "*="
    "/="
    "//="
    "|="
    "^="
    "÷="
    "%="
    "<<="
    ">>="
    ">>>="
    "\\="
    "&="
    ":="
    "~"
    "\$="
    "⊻="
    "≔"
    "⩴"
    "≕"

    "=>"

    "?"

    "-->"
    "<--"
    "<-->"
    "←"
    "→"
    "↔"
    "↚"
    "↛"
    "↞"
    "↠"
    "↢"
    "↣"
    "↤"
    "↦"
    "↮"
    "⇎"
    "⇍"
    "⇏"
    "⇐"
    "⇒"
    "⇔"
    "⇴"
    "⇶"
    "⇷"
    "⇸"
    "⇹"
    "⇺"
    "⇻"
    "⇼"
    "⇽"
    "⇾"
    "⇿"
    "⟵"
    "⟶"
    "⟷"
    "⟹"
    "⟺"
    "⟻"
    "⟼"
    "⟽"
    "⟾"
    "⟿"
    "⤀"
    "⤁"
    "⤂"
    "⤃"
    "⤄"
    "⤅"
    "⤆"
    "⤇"
    "⤌"
    "⤍"
    "⤎"
    "⤏"
    "⤐"
    "⤑"
    "⤔"
    "⤕"
    "⤖"
    "⤗"
    "⤘"
    "⤝"
    "⤞"
    "⤟"
    "⤠"
    "⥄"
    "⥅"
    "⥆"
    "⥇"
    "⥈"
    "⥊"
    "⥋"
    "⥎"
    "⥐"
    "⥒"
    "⥓"
    "⥖"
    "⥗"
    "⥚"
    "⥛"
    "⥞"
    "⥟"
    "⥢"
    "⥤"
    "⥦"
    "⥧"
    "⥨"
    "⥩"
    "⥪"
    "⥫"
    "⥬"
    "⥭"
    "⥰"
    "⧴"
    "⬱"
    "⬰"
    "⬲"
    "⬳"
    "⬴"
    "⬵"
    "⬶"
    "⬷"
    "⬸"
    "⬹"
    "⬺"
    "⬻"
    "⬼"
    "⬽"
    "⬾"
    "⬿"
    "⭀"
    "⭁"
    "⭂"
    "⭃"
    "⭄"
    "⭇"
    "⭈"
    "⭉"
    "⭊"
    "⭋"
    "⭌"
    "￩"
    "￫"
    "⇜"
    "⇝"
    "↜"
    "↝"
    "↩"
    "↪"
    "↫"
    "↬"
    "↼"
    "↽"
    "⇀"
    "⇁"
    "⇄"
    "⇆"
    "⇇"
    "⇉"
    "⇋"
    "⇌"
    "⇚"
    "⇛"
    "⇠"
    "⇢"
    "↷"
    "↶"
    "↺"
    "↻"

    "||"

    "&&"

    "<:"
    ">:"
    ">"
    "<"
    ">="
    "≥"
    "<="
    "≤"
    "=="
    "==="
    "≡"
    "!="
    "≠"
    "!=="
    "≢"
    "∈"
    "in"
    "isa"
    "∉"
    "∋"
    "∌"
    "⊆"
    "⊈"
    "⊂"
    "⊄"
    "⊊"
    "∝"
    "∊"
    "∍"
    "∥"
    "∦"
    "∷"
    "∺"
    "∻"
    "∽"
    "∾"
    "≁"
    "≃"
    "≂"
    "≄"
    "≅"
    "≆"
    "≇"
    "≈"
    "≉"
    "≊"
    "≋"
    "≌"
    "≍"
    "≎"
    "≐"
    "≑"
    "≒"
    "≓"
    "≖"
    "≗"
    "≘"
    "≙"
    "≚"
    "≛"
    "≜"
    "≝"
    "≞"
    "≟"
    "≣"
    "≦"
    "≧"
    "≨"
    "≩"
    "≪"
    "≫"
    "≬"
    "≭"
    "≮"
    "≯"
    "≰"
    "≱"
    "≲"
    "≳"
    "≴"
    "≵"
    "≶"
    "≷"
    "≸"
    "≹"
    "≺"
    "≻"
    "≼"
    "≽"
    "≾"
    "≿"
    "⊀"
    "⊁"
    "⊃"
    "⊅"
    "⊇"
    "⊉"
    "⊋"
    "⊏"
    "⊐"
    "⊑"
    "⊒"
    "⊜"
    "⊩"
    "⊬"
    "⊮"
    "⊰"
    "⊱"
    "⊲"
    "⊳"
    "⊴"
    "⊵"
    "⊶"
    "⊷"
    "⋍"
    "⋐"
    "⋑"
    "⋕"
    "⋖"
    "⋗"
    "⋘"
    "⋙"
    "⋚"
    "⋛"
    "⋜"
    "⋝"
    "⋞"
    "⋟"
    "⋠"
    "⋡"
    "⋢"
    "⋣"
    "⋤"
    "⋥"
    "⋦"
    "⋧"
    "⋨"
    "⋩"
    "⋪"
    "⋫"
    "⋬"
    "⋭"
    "⋲"
    "⋳"
    "⋴"
    "⋵"
    "⋶"
    "⋷"
    "⋸"
    "⋹"
    "⋺"
    "⋻"
    "⋼"
    "⋽"
    "⋾"
    "⋿"
    "⟈"
    "⟉"
    "⟒"
    "⦷"
    "⧀"
    "⧁"
    "⧡"
    "⧣"
    "⧤"
    "⧥"
    "⩦"
    "⩧"
    "⩪"
    "⩫"
    "⩬"
    "⩭"
    "⩮"
    "⩯"
    "⩰"
    "⩱"
    "⩲"
    "⩳"
    "⩵"
    "⩶"
    "⩷"
    "⩸"
    "⩹"
    "⩺"
    "⩻"
    "⩼"
    "⩽"
    "⩾"
    "⩿"
    "⪀"
    "⪁"
    "⪂"
    "⪃"
    "⪄"
    "⪅"
    "⪆"
    "⪇"
    "⪈"
    "⪉"
    "⪊"
    "⪋"
    "⪌"
    "⪍"
    "⪎"
    "⪏"
    "⪐"
    "⪑"
    "⪒"
    "⪓"
    "⪔"
    "⪕"
    "⪖"
    "⪗"
    "⪘"
    "⪙"
    "⪚"
    "⪛"
    "⪜"
    "⪝"
    "⪞"
    "⪟"
    "⪠"
    "⪡"
    "⪢"
    "⪣"
    "⪤"
    "⪥"
    "⪦"
    "⪧"
    "⪨"
    "⪩"
    "⪪"
    "⪫"
    "⪬"
    "⪭"
    "⪮"
    "⪯"
    "⪰"
    "⪱"
    "⪲"
    "⪳"
    "⪴"
    "⪵"
    "⪶"
    "⪷"
    "⪸"
    "⪹"
    "⪺"
    "⪻"
    "⪼"
    "⪽"
    "⪾"
    "⪿"
    "⫀"
    "⫁"
    "⫂"
    "⫃"
    "⫄"
    "⫅"
    "⫆"
    "⫇"
    "⫈"
    "⫉"
    "⫊"
    "⫋"
    "⫌"
    "⫍"
    "⫎"
    "⫏"
    "⫐"
    "⫑"
    "⫒"
    "⫓"
    "⫔"
    "⫕"
    "⫖"
    "⫗"
    "⫘"
    "⫙"
    "⫷"
    "⫸"
    "⫹"
    "⫺"
    "⊢"
    "⊣"
    "⟂"
    "⫪"
    "⫫"

    "<|"
    "|>"

    ":"
    ".."
    "…"
    "⁝"
    "⋮"
    "⋱"
    "⋰"
    "⋯"

    "\$"
    "+"
    "-" # also used for "−"
    "−"
    "++"
    "⊕"
    "⊖"
    "⊞"
    "⊟"
    "|"
    "∪"
    "∨"
    "⊔"
    "±"
    "∓"
    "∔"
    "∸"
    "≏"
    "⊎"
    "⊻"
    "⊽"
    "⋎"
    "⋓"
    "⧺"
    "⧻"
    "⨈"
    "⨢"
    "⨣"
    "⨤"
    "⨥"
    "⨦"
    "⨧"
    "⨨"
    "⨩"
    "⨪"
    "⨫"
    "⨬"
    "⨭"
    "⨮"
    "⨹"
    "⨺"
    "⩁"
    "⩂"
    "⩅"
    "⩊"
    "⩌"
    "⩏"
    "⩐"
    "⩒"
    "⩔"
    "⩖"
    "⩗"
    "⩛"
    "⩝"
    "⩡"
    "⩢"
    "⩣"
    "¦"

    "*"
    "/"
    "÷"
    "%"
    "⋅" # also used for lookalikes "·" and "·"
    "·"
    "·"
    "∘"
    "×"
    "\\"
    "&"
    "∩"
    "∧"
    "⊗"
    "⊘"
    "⊙"
    "⊚"
    "⊛"
    "⊠"
    "⊡"
    "⊓"
    "∗"
    "∙"
    "∤"
    "⅋"
    "≀"
    "⊼"
    "⋄"
    "⋆"
    "⋇"
    "⋉"
    "⋊"
    "⋋"
    "⋌"
    "⋏"
    "⋒"
    "⟑"
    "⦸"
    "⦼"
    "⦾"
    "⦿"
    "⧶"
    "⧷"
    "⨇"
    "⨰"
    "⨱"
    "⨲"
    "⨳"
    "⨴"
    "⨵"
    "⨶"
    "⨷"
    "⨸"
    "⨻"
    "⨼"
    "⨽"
    "⩀"
    "⩃"
    "⩄"
    "⩋"
    "⩍"
    "⩎"
    "⩑"
    "⩓"
    "⩕"
    "⩘"
    "⩚"
    "⩜"
    "⩞"
    "⩟"
    "⩠"
    "⫛"
    "⊍"
    "▷"
    "⨝"
    "⟕"
    "⟖"
    "⟗"
    "⌿"
    "⨟"

    "//"

    "<<"
    ">>"
    ">>>"

    "^"
    "↑"
    "↓"
    "⇵"
    "⟰"
    "⟱"
    "⤈"
    "⤉"
    "⤊"
    "⤋"
    "⤒"
    "⤓"
    "⥉"
    "⥌"
    "⥍"
    "⥏"
    "⥑"
    "⥔"
    "⥕"
    "⥘"
    "⥙"
    "⥜"
    "⥝"
    "⥠"
    "⥡"
    "⥣"
    "⥥"
    "⥮"
    "⥯"
    "￪"
    "￬"

    "::"

    "where"

    "."

    "!"
    "'"
    ".'"
    "->"

    "¬"
    "√"
    "∛"
    "∜"
]

const cutdown_tokens = [
    "#x\n"
    "#==#"
    " "
    "\t"
    "\n"
    "x"
    "β"
    "@"
    ","
    ";"

    "baremodule"
    "begin"
    "break"
    "const"
    "continue"
    "do"
    "export"
    "for"
    "function"
    "global"
    "if"
    "import"
    "let"
    "local"
    "macro"
    "module"
    "quote"
    "return"
    "struct"
    "try"
    "using"
    "while"
    "catch"
    "finally"
    "else"
    "elseif"
    "end"
    "abstract"
    "as"
    "doc"
    "mutable"
    "outer"
    "primitive"
    "type"
    "var"

    "1"
    "0b1"
    "0x1"
    "0o1"
    "1.0"
    "1.0f0"
    "\"s\""
    "'c'"
    "`s`"
    "true"
    "false"

    "["
    "]"
    "{"
    "}"
    "("
    ")"
    "\""
    "\"\"\""
    "`"
    "```"

    "="
    "+="
    "~"

    "=>"

    "?"

    "-->"

    "||"

    "&&"

    "<:"
    ">:"
    ">"
    "<"
    ">="
    "<="
    "=="
    "==="
    "!="

    "<|"
    "|>"

    ":"
    ".."
    "…"

    "\$"
    "+"
    "−"
    "-"
    "|"

    "*"
    "/"
    "⋅" # also used for lookalikes "·" and "·"
    "·"
    "\\"

    "//"

    "<<"

    "^"

    "::"

    "where"

    "."

    "!"
    "'"
    "->"

    "√"
]

#-------------------------------------------------------------------------------
# Parsing functions for use with fuzz_test

function try_parseall_failure(str)
    try
        JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, str, ignore_errors=true);
        return nothing
    catch exc
        !(exc isa InterruptException) || rethrow()
        rstr = reduce_text(str, parser_throws_exception)
        @error "Parser threw exception" rstr exception=current_exceptions()
        return rstr
    end
end

function try_hook_failure(str)
    try
        test_logger = Test.TestLogger()
        Logging.with_logger(test_logger) do
            Meta_parseall(str)
        end
        if !isempty(test_logger.logs)
            return str
        end
    catch exc
        return str
    end
    return nothing
end

#-------------------------------------------------------------------------------
"""Delete `nlines` adjacent lines from code, at `niters` randomly chosen positions"""
function delete_lines(lines, nlines, niters)
    selection = trues(length(lines))
    for j=1:niters
        i = rand(1:length(lines)-nlines)
        selection[i:i+nlines] .= false
    end
    join(lines[selection], '\n')
end

"""Delete `ntokens` adjacent tokens from code, at `niters` randomly chosen positions"""
function delete_tokens(code, tokens, ntokens, niters)
    # [ aa bbbb cc d eeeeee  ]
    #   |  |    |  | |     |
    selection = trues(length(tokens))
    for j=1:niters
        i = rand(1:length(tokens)-ntokens)
        selection[i:i+ntokens] .= false
    end
    io = IOBuffer()
    i = 1
    while true
        while i <= length(selection) && !selection[i]
            i += 1
        end
        if i > length(selection)
            break
        end
        first_ind = first(tokens[i].range)
        while selection[i] && i < length(selection)
            i += 1
        end
        last_ind = last(tokens[i].range)
        write(io, @view code[first_ind:last_ind])
        if i == length(selection)
            break
        end
    end
    return String(take!(io))
end

#-------------------------------------------------------------------------------
# Generators for "potentially bad input"

"""
Fuzz test parser against all tuples of length `N` with elements taken from
`tokens`.
"""
function product_token_fuzz(tokens, N)
    (join(ts) for ts in Iterators.product([tokens for _ in 1:N]...))
end

function random_token_fuzz(tokens, ntokens, ntries)
    (join(rand(tokens, ntokens)) for _ in 1:ntries)
end

"""
Fuzz test parser against randomly generated binary strings
"""
function random_binary_fuzz(nbytes, N)
    (String(rand(UInt8, nbytes)) for _ in 1:N)
end

"""
Fuzz test by deleting random lines of some given source `code`
"""
function deleted_line_fuzz(code, N; nlines=10, niters=10)
    lines = split(code, '\n')
    (delete_lines(lines, nlines, niters) for _=1:N)
end

"""
Fuzz test by deleting random tokens from given source `code`
"""
function deleted_token_fuzz(code, N; ntokens=10, niters=10)
    ts = tokenize(code)
    (delete_tokens(code, ts, ntokens, niters) for _=1:N)
end

"""
Fuzz test a parsing function by trying it with many "bad" input strings.

`try_parsefail` should return `nothing` when the parser succeeds, and return a
string (or reduced string) when parsing succeeds.
"""
function fuzz_test(try_parsefail::Function, bad_input_iter)
    error_strings = []
    for str in bad_input_iter
        res = try_parsefail(str)
        if !isnothing(res)
            push!(error_strings, res)
        end
    end
    return error_strings
end


# Examples
#
# fuzz_test(try_hook_failure, product_token_fuzz(cutdown_tokens, 2))
# fuzz_test(try_parseall_failure, product_token_fuzz(cutdown_tokens, 2))

