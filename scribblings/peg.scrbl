#lang scribble/manual
@(require (for-label peg
                     racket/base
                     racket/contract/base)
          scribble/bnf)

@title{PEG}

This library implements a PEG parser generator.
 
@section{Introduction}

PEG can be thought of as an advance over regex. It can match more languages (for example balanced brackets) and can be paired with semantic actions to produce structured results from a parse.

The PEG language is implemented as a system of macros that compiles parser descriptions (rules) into scheme code. It is also provided with a custom syntax via @racketmodfont{#lang peg}.

The generated code parses text by interacting with the "PEG VM", which is a set of registers holding the input text, input position, control stack for backtracking and error reporting notes.

@section{Syntax Reference}

@defmodule[peg]

@subsection{define-peg}

@defform*[((define-peg name rule)
           (define-peg name rule action))
  #:grammar ([<rule>
              (code:line (epsilon) (code:comment "always succeeds"))
	      (code:line (char c) (code:comment "matches the character c"))
	      (code:line (any-char) (code:comment "matches any character"))
	      (code:line (range c1 c2) (code:comment "match any char between c1 and c2"))
	      (code:line (string str) (code:comment "matches string str"))
	      (code:line (and <rule> ...) (code:comment "sequence"))
	      (code:line (or <rule> ...) (code:comment "prioritized choice"))
     	      (code:line (* <rule> ...) (code:comment "zero or more"))
     	      (code:line (+ <rule> ...) (code:comment "one or more"))
     	      (code:line (? <rule> ...) (code:comment "zero or one"))
     	      (code:line (?? <rule> ...) (code:comment "zero or one but #f when zero"))
     	      (code:line (call name))
     	      (code:line (name nm <rule>))
     	      (code:line (! <rule> ...) (code:comment "negative lookahead"))
	      (code:line (& <rule>) (code:comment "positive lookahead"))
     	      (code:line (drop <rule> ...) (code:comment "discard the semantic result on matching"))
	      ])]{
Defines a new scheme function named @racket[peg-rule:name] by compiling the peg rule into scheme code that interacts with the PEG VM.

If @racket[action] is supplied, it defines a semantic action to produce the result of the rule. Semantic actions are regular scheme expressions, they can refer to variables named by a @racket[capture].
}

We also provide shorthands for some common semantic actions:

@defform[(define-peg/drop name rule)]{
@code{= (define-peg rule-name (drop rule))}

makes the parser produce no result.
}

@defform[(define-peg/bake name rule)]{
@code{= (define-peg rule-name (name res rule) res)}

transforms the peg-result into a scheme object.
}

@defform[(define-peg/tag name rule)]{
@code{= (define-peg rule-name (name res exp) `(rule-name . ,res))}

tags the result with the peg rule name. Useful for parsers that create an AST.
}

@subsection{peg}

@defform[(peg rule input)
  #:contracts ([input (or/c string? input-port?)])]{
Runs a PEG parser and attempts to parse @racket[input] using the given @racket[rule]. This sets up the PEG VM registers into an initial state and then calls into the parser for @racket[rule].

If @racket[input] is a port, and @racket[(port-counts-lines? input)] returns @racket[#t], then parse errors will be reported at the actual position in the file. Otherwise, reported locations are relative to the point at which parsing started.
}

@section{Examples}

@subsection{Example 1}

For a simple example, lets try splitting a sentence into words. We can describe a word as one or more of non-space characters, optionally followed by a space:

@codeblock{
> (require peg)
> (define sentence "the quick brown fox jumps over the lazy dog")
> (define-peg non-space
    (and (! #\space) (any-char)))
> (define-peg/bake word
    (and (+ non-space)
         (drop (? #\space))))
> (peg word sentence)
"the"
> (peg (+ word) sentence)
'("the" "quick" "brown" "fox" "jumps" "over" "the" "lazy" "dog")
}

Using the peg lang, the example above is equal to
@verbatim{
#lang peg

(define sentence "the quick brown fox jumps over the lazy dog"); //yes, we can use
//one-line comments and any sequence of s-exps BEFORE the grammar definition

non-space <- (! ' ') . ; //the dot is "any-char" in peg
word <- c:(non-space+ ~(' ' ?)) -> c ; //the ~ is drop
//we can use ident:peg to act as (name ident peg).
//and rule <- exp -> action is equal to (define-peg rule exp action)
//with this in a file, we can use the repl of drracket to do exactly the
//uses of peg above.
}


@subsection{Example 2}

Here is a simple calculator example that demonstrates semantic actions and recursive rules.

@codeblock{
(define-peg number (name res (+ (range #\0 #\9)))
  (string->number res))
(define-peg sum
  (and (name v1 prod) (? (and #\+ (name v2 sum))))
  (if v2 (+ v1 v2) v1))
(define-peg prod
  (and (name v1 number) (? (and #\* (name v2 prod))))
  (if v2 (* v1 v2) v1))
}

this grammar in peg lang is equivalent to:

@codeblock{
#lang peg
number <- res:[0-9]+ -> (string->number res);
sum <- v1:prod ('+' v2:sum)? -> (if v2 (+ v1 v2) v1);
prod <- v1:number ('*' v2:prod)? -> (if v2 (* v1 v2) v1);
}

Usage:

@codeblock{
> (peg sum "2+3*4")
14
> (peg sum "2*3+4")
10
> (peg sum "7*2+3*4")
26
}

@subsection{Example 3}

Here is an example of parsing balanced parenthesis. It demonstrates a common technique of using @racket[_] for skipping whitespace, and using @racket[define-peg/bake] to produce a list rather than a sequence from a @racket[*].

@codeblock{
#lang racket
(require peg)

(define-peg/drop _ (* (or #\space #\newline)))

(define-peg symbol
  (and (name res (+ (and (! #\( #\) #\space #\newline) (any-char)))) _)
  (string->symbol res))

(define-peg/bake sexp
  (or symbol
      (and (drop #\() (* sexp) (drop #\) _))))
}

or in PEG syntax:

@codeblock{
#lang peg
_ < [ \n]*;
symbol <- res:(![() \n] .)+ _ -> (string->symbol res);
sexp <- s:symbol / ~'(' s:sexp* ~')' _ -> s;
// had to use s: -> s because there is no way to express bake from the PEG language
}

Usage:

@codeblock{
> (peg sexp "(foob (ar baz)quux)")
'(foob (ar baz) quux)
> (peg sexp "((())(()(())))")
'((()) (() (())))
> (peg sexp "(lambda (x) (list x (list (quote quote) x)))")
'(lambda (x) (list x (list 'quote x)))
}

@section{PEG Syntax}

This package also provides a @racketmodfont{#lang peg} alternative, to allow you to make parsers in a more standard PEG syntax.

@subsection{PEG Syntax Reference}

The best way to understand the PEG syntax would be by reference to examples, there are many simple examples in the racket peg repo and the follow is the actual grammar used by racket-peg to implemet the peg lang:

Note: When you match the empty string in peg lang, the result object is the empty sequence, not the empty string, be careful.

@verbatim{
#lang peg

(require "s-exp.rkt");

_ < ([ \t\n] / '//' [^\n]*)*;
SLASH < '/' _;

name <-- [a-zA-Z_] [a-zA-Z0-9\-_.]* _;

rule <-- name ('<--' / '<-' / '<') _ pattern ('->' _ s-exp _)? ';' _;
pattern <-- alternative (SLASH alternative)*;
alternative <-- expression+;
expression <-- (name ~':' _)? ([!&~] _)? primary ([*+?] _)?;
primary <-- '(' _ pattern ')' _ / '.' _ / literal / charclass / name;

literal <-- ~['] (~[\\] ['\\] / !['\\] .)* ~['] _;

charclass <-- ~'[' '^'? (cc-range / cc-escape / cc-single)+ ~']' _;
cc-range <-- cc-char ~'-' cc-char;
cc-escape <-- ~[\\] .;
cc-single <-- cc-char;
cc-char <- !cc-escape-char . / 'n' / 't';
cc-escape-char <- '[' / ']' / '-' / '^' / '\\' / 'n' / 't';

peg <-- _ import* rule+;
import <-- s-exp _ ';' _;
}
