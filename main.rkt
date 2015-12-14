#lang racket/base



(require racket/contract
         racket/match
         racket/string
         racket/tcp
         
         srfi/19
         
         web-server/private/util)


(provide define-method
         register-method!
         serve!
         call
         call!
         on-terminate
         server-readtable)



(define (raise-message-error expected received)
  (raise (exn:fail (format "bad message: expected ~a, received: ~a" expected received)
                   (current-continuation-marks))))




(define-logger ss-rpc)
(current-logger ss-rpc-logger)


(define (init-logger log-receiver out)
  (thread 
   (λ ()
      (let loop ()
        (define v (sync log-receiver))

        (define header (format "[~a ~a]"
                               (vector-ref v 0)
                               (date->string (current-date) "~H:~M:~S")))
        (write-string (format "~a ~a\n"
                              header
                              (string-join (string-split (vector-ref v 1) "\n")
                                           (string-append "\n" (make-string (add1 (string-length header))
                                                                            #\space))))
                      out)
        (flush-output out)
        (loop)))))




(define method-ht (make-hasheq))
(define (method? x) (hash-has-key? method-ht x))
(define (get-method key) (hash-ref method-ht key))

(define/contract (register-method! x key)
  (-> procedure? symbol? void?)
  (hash-set! method-ht key x))

(define-syntax-rule (define-method (id . rest) body ...)
  (begin
    (define (id . rest) body ...)
    (register-method! id 'id)))




(define vector-exit (box 42))
(define (vector-exit? v) (eq? v vector-exit))

(define server-readtable
  (make-parameter
   (make-readtable (current-readtable)
                   #\n 'non-terminating-macro (λ (c in . _)
                                                 (match (read in)
                                                   ['il null]
                                                   [x (string->symbol (format "n~a" x))]))
                   #\[ 'terminating-macro (λ (c in . _)
                                             (list->vector
                                              (let loop ()
                                                (match (read in)
                                                  [(? vector-exit? _) '()]
                                                  [x (cons x (loop))]))))
                   #\] 'terminating-macro (λ (c in . _)
                                             vector-exit)
                   #\s 'dispatch-macro (λ (c in . _)
                                          (match (read in)
                                            [(list _ ... 'data (list kv ...))
                                             (apply hash kv)]
                                            [x (raise-syntax-error #f "expected emacs lisp hash table syntax" x)])))))




(define (log-server-error e)
  (define error-message (format "server ss-rpc error:\n~a" (exn->string e)))
  (send-list! (list 'return-error error-message))
  (log-ss-rpc-fatal error-message))



(define-values (in out) (values #f #f))

(define on-terminate (make-parameter void))

(define exit (box 1))
(define (exit? x) (eq? x exit))

(define/contract (serve! #:log-level [log-level 'info]
                         #:log-out [log-out (current-output-port)])
  (->* () (#:log-level (or/c 'none 'fatal 'error 'warning 'info 'debug)
                       #:log-out output-port?) void?)
  
  (init-logger (make-log-receiver ss-rpc-logger log-level)
               log-out)
  
  
  (define listener (tcp-listen 0 4 #f "localhost"))
  
  (define-values (_ port __ ___) (tcp-addresses listener #t))
  (display port)
  (flush-output)
  (log-ss-rpc-info "start listening on ~a" port)
  (set!-values (in out) (tcp-accept listener))
  (log-ss-rpc-info "accepted connection")
    
  (parameterize ([current-output-port log-out])
    (with-handlers ([(λ (x) (eq? x 'terminate)) (λ _
                                                   ((on-terminate))
                                                   (log-ss-rpc-info "closing server")
                                                   (send-list! '(exit)))])
      (let loop ()
        (with-handlers ([exn:fail? log-server-error]
                        [exit?  (λ _ (log-ss-rpc-debug "exit to handle-c-cv-t! loop"))])
          (handle-c-cv-t!))
        (loop))))

  (close-output-port log-out)
  (sleep 0.2))




(define ((failed-call-pusher proc args)  _)
  (log-ss-rpc-error "SERVER->CLIENT CALL STACK: ~a ~a" proc args)
  (raise exit))

(define ((server-fail-handler proc args) e)
  (log-server-error e)
  ((failed-call-pusher proc args) e))


(define/contract (call method . args)
  (->* (symbol?) #:rest (listof any/c) any/c)
  (with-handlers ([exn:fail? (server-fail-handler method args)]
                  [exit? (failed-call-pusher method args)])
    (send-list! (list 'call method args))
    (handle-r-re-c-cv)))


(define/contract (call! method . args)
  (->* (symbol?) #:rest (listof any/c) void?)
  (with-handlers ([exn:fail? (server-fail-handler method args)]
                  [exit? (failed-call-pusher method args)])
    (send-list! (list 'call-void method args))
    (handle-rv-re-c-cv!)))


    


(define (get-message)
  (define message (parameterize ([current-readtable (server-readtable)])
                    (read in)))
  (log-ss-rpc-debug "received ~a" message)
  message)



(define (handle-c-cv-t!)
  (match (get-message)
    [(list 'call method args) (handle-call! method args)]
    [(list 'call-void method args) (handle-call-void! method args)]
    [(list 'terminate) (raise 'terminate)]
    [x (raise-message-error "call | call-void | terminate" x)]))



(define (handle-re-c-cv message handler error-prefix)
  (match message
    [(list 'call method args)
     (handle-call! method args)
     (handler)]
    
    [(list 'call-void method args)
     (handle-call-void! method args)
     (handler)]
    
    [(list 'return-error x) (handle-error x)]
    
    [x (raise-message-error (format "~a | return-error | call | call-void" error-prefix) x)]))


(define (handle-r-re-c-cv)
  (match (get-message)
    [(list 'return x) x]    
    [x (handle-re-c-cv x handle-r-re-c-cv "return")]))


(define (handle-rv-re-c-cv!)
  (match (get-message)
    [(list 'return-void) (void)]
    [x (handle-re-c-cv x handle-rv-re-c-cv! "return-void")]))



(define (send-list! lst)
  (log-ss-rpc-debug "sending ~a" lst)
  (write lst out)
  (flush-output out))


(define (application-fail-handler e)
  (define em (format "server procedure application error:\n~a" (exn->string e)))
  (log-ss-rpc-error em)
  (send-list! (list 'return-error em))
  (raise exit))



(define/contract (handle-call! method-symbol args)
  (-> method? list? void?)
  (with-handlers ([exn:fail? application-fail-handler])
    (send-list! (list 'return (apply (get-method method-symbol) args)))))


(define/contract (handle-call-void! method-symbol args)
  (-> method? list? void?)
  (with-handlers ([exn:fail? application-fail-handler])
    (apply (get-method method-symbol) args))
  (send-list! '(return-void)))


(define (handle-error message)
  (log-ss-rpc-error message)
  (raise exit))



