#lang racket/base
(require (prefix-in scribble: scribble/reader)
         (rename-in syntax/module-reader
                    [#%module-begin #%reader-module-begin]))
(provide (rename-out [module-begin #%module-begin])
         (except-out (all-from-out racket/base)
                     #%module-begin)
         scribble-base-info
         scribble-base-reader-info
         scribble-base-language-info)

(define-syntax-rule (module-begin lang #:wrapper1 wrapper1)
  (#%reader-module-begin
   lang

   #:read          scribble:read-inside
   #:read-syntax   scribble:read-syntax-inside
   #:whole-body-readers? #t
   #:wrapper1      wrapper1
   #:info          (scribble-base-info)
   #:language-info (scribble-base-language-info)))

;; Settings that apply just to the surface syntax:
(define (scribble-base-reader-info)
  (lambda (key defval default)
    (define (try-dynamic-require lib export)
      (with-handlers ([exn:missing-module?
                       (λ (x) (default key defval))])
        (dynamic-require lib export)))
    (case key
      [(color-lexer)
       (try-dynamic-require 'syntax-color/scribble-lexer 'scribble-inside-lexer)]
      [(drracket:indentation)
       (try-dynamic-require 'scribble/private/indentation 'determine-spaces)]
      [(drracket:keystrokes)
       (try-dynamic-require 'scribble/private/indentation 'keystrokes)]
      [(drracket:default-extension) "scrbl"]
      [(drracket:comment-delimiters)
       '((line "@;" " "))]
      [(drracket:define-popup)
       (try-dynamic-require 'scribble/private/define-popup 'define-popup)]
      [else (default key defval)])))

;; Settings that apply to Scribble-renderable docs:
(define (scribble-base-info)
  (lambda (key defval default)
    (case key
      [(drracket:toolbar-buttons)
       (dynamic-require 'scribble/tools/drracket-buttons 'drracket-buttons)]
      [else ((scribble-base-reader-info) key defval default)])))

(define (scribble-base-language-info)
  '#(racket/language-info get-info #f))
