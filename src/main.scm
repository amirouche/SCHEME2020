(import (scheme base))
(import (scheme bitwise))
(import (scheme case-lambda))
(import (scheme char))
(import (scheme charset))
(import (scheme cxr))
(import (scheme eval))
(import (scheme list))
(import (scheme read))
(import (scheme sort))
(import (scheme write))

(import (srfi 125))
(import (srfi 128))
(import (srfi 129))
(import (srfi 146 hash))
(import (srfi 146))
(import (srfi 158))
(import (srfi 167 memory))
(import (srfi 168))
(import (srfi 180))

(import (chibi emscripten))
(import (chibi match))
(import (chibi parse))


(write-string "Chibi Scheme is running...\n")

(eval-script! "document.resume = Module['resume']")

;; scheme helpers

(define (eval-string string)
  (eval (string->scm string) (environment '(scheme base))))

(define-syntax define-syntax-rule
  (syntax-rules ()
    ((define-syntax-rule (keyword args ...) body)
     (define-syntax keyword
       (syntax-rules ()
         ((keyword args ...) body))))))

(define (assume v)
  (unless v
    (error "assume error" v)))

(define (call-with-output-string proc)
  (let ((port (open-output-string)))
    (proc port)
    (get-output-string port)))

(define (scm->string scm)
  (call-with-output-string (lambda (port) (write scm port))))

(define (call-with-input-string string proc)
  (let ((port (open-input-string string)))
    (proc port)))

(define (string->scm string)
  (call-with-input-string string read))

(define (dg . args)
  (write-string (scm->string args))
  (newline))

(define (pk . args)
  (apply dg args)
  (car (reverse args)))

(define (acons a b alist)
  (cons (cons a b) alist))

(define (rm alist key)
  (let loop ((alist alist)
             (out '()))
    (if (null? alist)
        out
        (if (equal? (caar alist) key)
            (append out (cdr alist))
            (loop (cdr alist) (cons (car alist) out))))))

(define (set alist key value)
  (acons key value (rm alist key)))

(define (ref alist key)
  (let loop ((alist alist))
    (cond
     ((null? alist) #f)
     ((equal? (caar alist) key) (cdar alist))
     (else (loop (cdr alist))))))

;; emulate a prompt with call/cc

(define %prompt #f)
(define %escape (list 'escape))

(define (call-with-prompt thunk handler)
  (call-with-values (lambda ()
                      (call/cc
                       (lambda (k)
                         (set! %prompt k)
                         (thunk))))
    (lambda out
      (cond
       ((and (pair? out) (eq? (car out) %escape))
        (apply handler (cdr out)))
       (else (apply values out))))))

(define (abort-to-prompt . args)
  (call/cc
   (lambda (k)
     (let ((prompt %prompt))
       (set! %prompt #f)
       (apply prompt (cons %escape (cons k args)))))))

;;; Commentary
;;
;; TODO: something insightful
;;

(define (make-node tag options children)
  `((tag . ,(symbol->string tag))
    (options . ,options)
    (children . ,(list->vector children))))

(define (magic attrs next-identifier)
  ;; shake around the attrs to make them compatible with
  ;; react-hyperscript options, associate callbacks to integer
  ;; identifiers. The event on a given node is associated with an
  ;; integer, the integer is associated with a callback
  ;; procedure. Return both react-hyperscript options and
  ;; integer-to-callback alist named `callbacks`.

  (define (rename event)
    (string->symbol (string-append "on" (string-titlecase (symbol->string event)))))

  (define (magic* next-identifier events)
    (let loop ((next-identifier next-identifier)
               (events events)
               (callbacks '())
               (events* '()))
      (if (null? events)
          (values next-identifier callbacks events*)
          (let ((name (caar events))
                (callback (cadar events)))
            (loop (+ next-identifier 1)
                  (cdr events)
                  (acons next-identifier callback callbacks)
                  (acons (rename name) next-identifier events*))))))

  (let loop ((attrs attrs)
             (next-identifier next-identifier)
             (out '())
             (callbacks '()))
    (if (null? attrs)
        (values out callbacks)
        (match attrs
          ;; handle style attribute
          ((('style style) rest ...)
           (loop rest
                 next-identifier
                 (acons 'style (make-style style) out)
                 callbacks))
          ;; handle on events attribute
          ((('on events) rest ...)
           (call-with-values (lambda () (magic* next-identifier events))
             (lambda (next-identifier* callbacks* events*)
               (loop rest
                     next-identifier*
                     (append out events*)
                     (append callbacks callbacks*)))))
          ;; plain attributes
          (((key value) rest ...)
           (loop rest
                 next-identifier
                 (acons key value out)
                 callbacks))
          (else (error 'magic "no matching pattern"))))))

(define (%sxml->hyperscript+callbacks sxml callbacks)
  (match sxml
    ((? string? string)
     (values string '()))
    ((tag ('@ attrs ...) rest ...)
     (call-with-values (lambda () (magic attrs (length callbacks)))
       (lambda (attrs new-callbacks)
         (let loop ((callbacks (append callbacks new-callbacks))
                    (rest rest)
                    (out '()))
           (if (null? rest)
               (values (make-node tag attrs (reverse out)) callbacks)
               (call-with-values (lambda () (%sxml->hyperscript+callbacks (car rest) callbacks))
                 (lambda (hyperscript new-callbacks)
                   (loop (append callbacks new-callbacks)
                         (cdr rest)
                         (cons hyperscript out)))))))))
    ((tag rest ...)
     ;; there is no magic but almost the same as above loop.
     (let loop ((callbacks callbacks)
                (rest rest)
                (out '()))
       (if (null? rest)
           (values (make-node tag '() (reverse out)) callbacks)
           (call-with-values (lambda () (%sxml->hyperscript+callbacks (car rest) callbacks))
             (lambda (hyperscript callbacks)
               (loop callbacks (cdr rest) (cons hyperscript out)))))))
    (else (error 'sxml "no matching pattern"))))

(define (sxml->hyperscript+callbacks sxml)
  (%sxml->hyperscript+callbacks sxml '()))

;;; style helpers:
;;
;; make-style: translate css styles to reactjs styles
;;
;; https://css-tricks.com/snippets/css/a-guide-to-flexbox/
;;
;; see ./static/normalize.css
;;

(define (->reactjs symbol)
  (let loop ((chars (string->list (symbol->string symbol)))
             (out '()))
    (if (null? chars)
        (string->symbol (list->string (reverse out)))
        (if (char=? (car chars) #\-)
            (loop (cddr chars) (cons (char-upcase (cadr chars)) out))
            (loop (cdr chars) (cons (car chars) out))))))

(define (make-style alist)
  (let loop ((alist alist)
             (out '()))
    (if (null? alist)
        out
        (loop (cdr alist) (acons (->reactjs (caar alist)) (cdar alist) out)))))

;; override

(define (%%merge first second)
  (let loop ((second second)
             (out first))
    (if (null? second)
        out
        (loop (cdr second) (set out (caar second) (cdar second))))))

(define (%merge first rest)
  (let loop ((rest rest)
             (out first))
    (if (null? rest)
        out
        (loop (cdr rest) (%%merge out (car rest))))))

(define (merge first second . other)
  (%merge first (cons second other)))

;; inbox handling

(define (recv-from-javascript)
  (call-with-input-string (string-eval-script "document.scheme_inbox")
                          json-read))

(define (send-to-javascript! obj)
  (let ((json (call-with-output-string (lambda (port) (json-write obj port)))))
    (eval-script! (string-append "document.javascript_inbox = " json ";"))))

(define (xhr method path obj)
  (abort-to-prompt (vector "xhr" (vector method path obj))))

(define (create-app init view)
  (define model (okvs-open #f))

  (okvs-in-transaction model (lambda (txn) (init txn)))

  (let loop0 ()
    (let ((sxml (okvs-in-transaction model (lambda (txn) (view txn)))))
      (call-with-values (lambda () (sxml->hyperscript+callbacks sxml))
        (lambda (hyperscript callbacks)
          (send-to-javascript! (vector "patch" hyperscript))
          (wait-on-event!)
          (let loop1 ((event (recv-from-javascript))
                      (k #f))
            (cond
             ((and (string=? (vector-ref event 0) "xhr") k)
              (k (vector-ref event 1)))
             ((string=? (vector-ref event 0) "event")
              (call-with-prompt
               (lambda ()
                 (let* ((event (vector-ref event 1))
                        (identifier (ref event 'identifier))
                        (callback (ref callbacks identifier)))
                   (okvs-in-transaction model (lambda (txn) (callback txn event)))
                   (loop0)))
               (lambda (k obj)
                 (send-to-javascript! obj)
                 (wait-on-event!)
                 (loop1 (recv-from-javascript) k)))))))))))

;; app

(define triplestore (nstore (make-default-engine) (list) '(uid key value)))

(define data
  '(("scheme" "is" "programming language")
    ;; chez data
    ("chez" "is" "scheme")
    ("chez" "name" "Chez Scheme")
    ("chez" "licence" "Apache 2.0")
    ("chez" "tag line" "The fastest Scheme")
    ("chez" "description" "Chez Scheme is both a programming language and an implementation of that language, with supporting tools and documentation.

As a superset of the language described in the Revised6 Report on the Algorithmic Language Scheme (R6RS), Chez Scheme supports all standard features of Scheme, including first-class procedures, proper treatment of tail calls, continuations, user-defined records, libraries, exceptions, and hygienic macro expansion.

Chez Scheme also includes extensive support for interfacing with C and other languages, support for multiple threads possibly running on multiple cores, non-blocking I/O, and many other features.")
    ("chez" "GNU/Linux" #t)
    ("chez" "Windows" #t)
    ("chez" "R6RS" #t)
    ("chez" "R7RS" #f)
    ;; arew data
    ("arew" "is" "scheme")
    ("arew" "name" "Arew Scheme")
    ("arew" "licence" "AGPLv3")
    ("arew" "tag line" "The fastest Scheme with R7RS batteries included")
    ("arew" "description" "Arew Scheme is a Chez Scheme distribution with R7RS libraries.")
    ("arew" "GNU/Linux" #t)
    ("arew" "Windows" #f)
    ("arew" "R6RS" #t)
    ("arew" "R7RS" #t)))

(define (init txn)
  (let loop ((data data))
    (unless (null? data)
      (nstore-add! txn triplestore (car data))
      (loop (cdr data))))
  (nstore-add! txn triplestore (list 'filter 'R7RS #f)))

(define (filter-ref txn name)
  (hashmap-ref ((nstore-from txn triplestore (list 'filter name (nstore-var 'var)))) 'var))

(define (filter-set! txn name boolean)
  (nstore-delete! txn triplestore (list 'filter name (filter-ref txn name)))
  (nstore-add! txn triplestore (list 'filter name boolean)))

(define (filter-toggle txn name)
  (let ((boolean (filter-ref txn name)))
    (filter-set! txn name (not boolean))))

(define headers '("name" "licence" "GNU/Linux" "Windows" "R6RS" "R7RS"))

(define (query-schemes txn)
  (generator-map->list
   (lambda (x) (hashmap-ref x 'scheme))
   (nstore-from txn triplestore
                (list (nstore-var 'scheme) "is" "scheme"))))

(define (table headers rows)
  `(table
    (thead
     (tr
      ,@(map (lambda (title) `(th ,title)) headers)))
    (tbody
     ,@(let loop ((rows rows)
                  (out '()))
         (if (null? rows)
             out
             (loop (cdr rows)
                   (cons `(tr ,@(map (lambda (x) `(td ,x)) (car rows))) out)))))))

(define (->ok boolean)
  (if boolean "ok" "ko"))

(define (query-scheme txn scheme)
  ((nstore-query
    (nstore-from txn triplestore
                 (list scheme "name" (nstore-var 'name)))
    (nstore-where txn triplestore
                  (list scheme "tag line" (nstore-var 'tag-line)))
    (nstore-where txn triplestore
                  (list scheme "licence" (nstore-var 'licence)))
    (nstore-where txn triplestore
                  (list scheme "GNU/Linux" (nstore-var 'GNU/Linux)))
    (nstore-where txn triplestore
                  (list scheme "Windows" (nstore-var 'Windows)))
    (nstore-where txn triplestore
                  (list scheme "R6RS" (nstore-var 'R6RS)))
    (nstore-where txn triplestore
                  (list scheme "R7RS" (nstore-var 'R7RS))))))

(define (query-scheme-row txn name)
  (generator-map->list
   (lambda (x) (list (hashmap-ref x 'name)
                     (hashmap-ref x 'licence)
                     (->ok (hashmap-ref x 'GNU/Linux))
                     (->ok (hashmap-ref x 'Windows))
                     (->ok (hashmap-ref x 'R6RS))
                     (->ok (hashmap-ref x 'R7RS))))
   (nstore-query
    (nstore-from txn triplestore
                 (list name "name" (nstore-var 'name)))
    (nstore-where txn triplestore
                  (list name "licence" (nstore-var 'licence)))
    (nstore-where txn triplestore
                  (list name "GNU/Linux" (nstore-var 'GNU/Linux)))
    (nstore-where txn triplestore
                  (list name "Windows" (nstore-var 'Windows)))
    (nstore-where txn triplestore
                  (list name "R6RS" (nstore-var 'R6RS)))
    (nstore-where txn triplestore
                  (list name "R7RS" (nstore-var 'R7RS))))))

(define (query txn)
  (let ((schemes (query-schemes txn)))
    (map (lambda (name) (query-scheme-row txn name)) schemes)))

(define (make-tag symbol)
  `(li (@ (style ((background . "#f45e61")
                  (border-radius . "3px")
                  (display . "inline-block")
                  (margin-right . "5px")
                  (padding . "5px")
                  (color . "black"))))
       ,(symbol->string symbol)))

(define (box-scheme txn scheme)
  (let ((scheme (query-scheme txn scheme)))
    `(div (@ (id "box"))
          (h3 ,(hashmap-ref scheme 'name))
          (p ,(hashmap-ref scheme 'tag-line))
          (p "Licence: " ,(hashmap-ref scheme 'licence))
          (ul ,@(let loop ((symbols '(GNU/Linux Windows R6RS R7RS))
                           (out '()))
                  (if (null? symbols)
                      out
                      (if (hashmap-ref scheme (car symbols))
                          (loop (cdr symbols) (cons (make-tag (car symbols))
                                                    out))
                          (loop (cdr symbols) out))))))))

(define style/basic
  '((border . "2px solid hsla(0, 100%, 100%, 0.8)")
    (border-radius . "3px")
    (padding . "15px 30px")
    (margin-bottom . "15px")
    (background . "hsla(0, 0%, 0%, 0.4)")))

(define (view txn)
  `(div
    (nav (@ (className "navbar navbar-light bg-light"))
         (a (@ (className "navbar-brand")) "news")
         (form (@ (className "form-inline"))
               (input (@ (className "form-control mr-sm-2")
                         (type "search")
                         (placeholder "Search")))
               (button (@ (className "btn btn-outline-success my-2 my-sm-0")
                          (type "submit")) "Search")))))


(pk "starting application...")
(create-app init view)

;; everything that follows is dead code
