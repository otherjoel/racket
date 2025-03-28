#lang racket/base
(require "../common/struct-star.rkt"
         "../syntax/syntax.rkt"
         "../syntax/scope.rkt"
         "../syntax/taint.rkt"
         "../namespace/core.rkt"
         "../syntax/match.rkt"
         "../syntax/error.rkt"
         "../syntax/module-binding.rkt"
         "../namespace/namespace.rkt"
         "require+provide.rkt"
         "main.rkt"
         "parsed.rkt"
         "context.rkt"
         "require.rkt"
         "def-id.rkt"
         "bind-top.rkt"
         "lift-context.rkt"
         "lift-key.rkt"
         "log.rkt"
         "portal-syntax.rkt"
         "top-portal-syntax.rkt")

(add-core-form!
 'define-values
 (lambda (s ctx)
   (log-expand ctx 'prim-define-values s)
   (unless (eq? (expand-context-context ctx) 'top-level)
     (raise-syntax-error #f "not allowed in an expression position" s))
   (define-match m s '(define-values (id ...) rhs))
   (define-values (ids syms) (as-expand-time-top-level-bindings (m 'id) s ctx))
   (define exp-rhs (expand (m 'rhs) (as-named-context (as-expression-context ctx) ids)))
   (if (expand-context-to-parsed? ctx)
       (parsed-define-values s ids syms exp-rhs)
       (rebuild
        s
        `(,(m 'define-values) ,ids ,exp-rhs)))))

(add-core-form!
 'define-syntaxes
 (lambda (s ctx)
   (log-expand ctx 'prim-define-syntaxes s)
   (unless (eq? (expand-context-context ctx) 'top-level)
     (raise-syntax-error #f "not in a definition context" s))
   (define-match m s '(define-syntaxes (id ...) rhs))
   (define-values (ids syms) (as-expand-time-top-level-bindings (m 'id) s ctx))
   (log-expand ctx 'prepare-env)
   (define exp-rhs (expand-transformer (m 'rhs) (as-named-context ctx ids)))
   (if (expand-context-to-parsed? ctx)
       (parsed-define-syntaxes s ids syms exp-rhs)
       (rebuild
        s
        `(,(m 'define-syntaxes) ,ids ,exp-rhs)))))

(add-core-form!
 'begin-for-syntax
 (lambda (s ctx)
   (log-expand ctx 'prim-begin-for-syntax #f)
   (unless (eq? (expand-context-context ctx) 'top-level)
     (raise-syntax-error #f "not in a definition context" s))
   (define-match m s '(begin-for-syntax form ...))
   (log-expand ctx 'prepare-env)
   (define trans-ctx (context->transformer-context ctx 'top-level #:keep-stops? #t))
   (define lift-ctx (make-lift-context
                     (make-top-level-lift trans-ctx)))
   (define capture-ctx (struct*-copy expand-context trans-ctx
                                     [lift-key #:parent root-expand-context (generate-lift-key)]
                                     [lifts lift-ctx]))
   (define all-exp-forms
     (let loop ([forms (m 'form)])
       (log-expand ctx 'enter-list (m 'form))
       (define exp-forms
         (let loop ([forms forms] [accum null])
           (cond
             [(null? forms)
              (define forms (reverse accum))
              (log-expand ctx 'exit-list forms)
              forms]
             [else
              (log-expand ctx 'next)
              (define exp-form (expand (car forms) capture-ctx))
              (loop (cdr forms) (cons exp-form accum))])))
       (define lifts (get-and-clear-lifts! lift-ctx))
       (cond
         [(null? lifts)
          exp-forms]
         [else
          (log-expand ctx 'module-lift-loop lifts)
          (define beg (wrap-lifts-as-begin lifts #f (expand-context-phase trans-ctx)))
          (define exprs (reverse (cdr (reverse (cdr (syntax-e beg))))))
          (append (loop exprs) exp-forms)])))
   ;; We shouldn't be able to get here in to-parsed mode
   (if (expand-context-to-parsed? ctx)
       (parsed-begin-for-syntax s all-exp-forms)
       (rebuild s (cons (m 'begin-for-syntax) all-exp-forms)))))

(add-core-form!
 '#%require
 (lambda (s ctx)
   (log-expand ctx 'prim-require s)
   (unless (eq? (expand-context-context ctx) 'top-level)
     (raise-syntax-error #f "allowed only in a module or the top level" s))
   (define-match m s '(#%require req ...))
   (define sc (new-scope 'macro)) ; to hide bindings
   (define ns (expand-context-namespace ctx))
   (define generated-syms (box null)) ; support portal symbol recording
   ;; Check the `#%require` form syntax and trigger compile-time
   ;; instanations
   (parse-and-perform-requires! (for/list ([req (in-list (m 'req))])
                                  (add-scope req sc))
                                s
                                #:self (namespace-self-mpi/no-top-level ns)
                                #:visit? #f
                                ns
                                (expand-context-phase ctx)
                                (make-requires+provides #f)
                                #:who 'require
                                ;; We don't need to check for conflicts:
                                #:initial-require? #t
                                #:add-defined-portal (make-top-add-defined-portal ns ctx generated-syms))
   ;; Nothing to expand
   (if (expand-context-to-parsed? ctx)
       (parsed-require s (reverse (unbox generated-syms)))
       s)))

(add-core-form!
 '#%provide
 (lambda (s ctx)
   (log-expand ctx 'prim-provide #f)
   (raise-syntax-error #f "not allowed outside of a module body" s)))
