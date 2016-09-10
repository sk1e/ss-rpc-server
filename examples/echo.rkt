#lang racket/base

(require ss-rpc-server)

(define-method (echo x) x)
(serve!)


(module test racket/base) ;; skip module testing
