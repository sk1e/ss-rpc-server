#lang scribble/manual
@(require
   scribble/eval
   scribble/base
   (for-label racket ss-rpc-server)
   )


@title{SS-RPC server}

@(define server-eval (make-base-eval))
@interaction-eval[#:eval server-eval
                   (require ss-rpc-server)]


@author[@author+email["Sergey Petrov" "sekk1e@yandex.ru"]]


@italic["SS-RPC"] is a Synchronous S-expression-based Remote Procedure Call,
facility to call procedure within remote process and receive
return value. SS-RPC allows you to use Racket as GNU Emacs extension language.
It includes a server described by this page and a
@link["https://github.com/sk1e/ss-rpc-client" "client"] for Emacs.

@section{Features and limitations}

SS-RPC uses S-expressions as message language and TCP/IP
as transport. Main advantages of SS-RPC over other RPCs for
Emacs are lower remote call overhead and a feature of mutual
remote call between server and client.

SS-RPC is limited with synchronous calls and transmitted data structures
which are defined by the intersection of Emacs Lisp and Racket readers.


@section{Server API}

@defmodule[ss-rpc-server]


@defproc[(register-method! [x procedure?] [key symbol?]) void?]{
                                                                
  Puts a procedure @racket[x] to a method table that can be accessed from client by a @racket[key].}



@defform[(define-method (id args) body ...+)
         ]{
 Syntactic wrapper for @racket[define] with a registering as a method with its symbol.
                                                     
  @interaction[#:eval server-eval
            (define-method (echo x) x)]

  is a shorthand for
  @interaction[#:eval server-eval
            (define (echo x) x)
            (register-method! echo 'echo)]}

@defproc[(serve! [#:log-level log-level (or/c 'none 'fatal 'error 'warning 'info 'debug) 'info]
                 [#:log-out log-out output-port? (current-output-port)]) void?]{
                                                                
  Enters a serving loop with handling incoming commands.}



@defproc[(call [method symbol?] [arg any/c] ...) any/c]{
                                                                
  Applies a elisp procedure @racket[method] to @racket[arg]s as its arguments and returns the result
        of application. Note, that elisp client does not registers remote procedures and @racket[method] can be any
        elisp procedure symbol.}



@defproc[(call! [method symbol?] [arg any/c] ...) void?]{
                                                                
  Applies a elisp procedure @racket[method] to @racket[arg]s as its arguments with @bold["ignoring"] the return result
        of application. Note, that elisp client does not registers remote procedures and @racket[method] can be any
        elisp procedure symbol.}



@defparam[on-terminate proc (-> any/c) #:value void]{
 Deinitialization procedure which will be applied on receiving @italic["terminate"] command.}

@defparam[server-readtable x readtable? #:value readtable?]{
 Readtable to read incoming message. Currently reads nil symbol as empty list, elisp vectors and hashtables}
