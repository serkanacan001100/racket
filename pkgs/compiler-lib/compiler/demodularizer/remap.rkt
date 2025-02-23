#lang racket/base
(require racket/match
         racket/set
         compiler/zo-structs)

(provide remap-positions
         remap-names)

(define (remap-positions body
                         remap-toplevel-pos ; integer -> integer
                         #:application-hook [application-hook (lambda (rator rands remap) #f)])
  (define graph (make-hasheq))
  (make-reader-graph
   (for/list ([b (in-list body)])
     (let remap ([b b])
       (match b
         [(toplevel depth pos const? ready?)
          (define new-pos (remap-toplevel-pos pos))
          (toplevel depth new-pos const? ready?)]
         [(def-values ids rhs)
          (def-values (map remap ids) (remap rhs))]
         [(inline-variant direct inline)
          (inline-variant (remap direct) (remap inline))]
         [(closure code gen-id)
          (cond
            [(hash-ref graph gen-id #f)
             => (lambda (ph) ph)]
            [else
             (define ph (make-placeholder #f))
             (hash-set! graph gen-id ph)
             (define cl (closure (remap code) gen-id))
             (placeholder-set! ph cl)
             cl])]
         [(let-one rhs body type unused?)
          (let-one (remap rhs) (remap body) type unused?)]
         [(let-void count boxes? body)
          (let-void count boxes? (remap body))]
         [(install-value count pos boxes? rhs body)
          (install-value count pos boxes? (remap rhs) (remap body))]
         [(let-rec procs body)
          (let-rec (map remap procs) (remap body))]
         [(boxenv pos body)
          (boxenv pos (remap body))]
         [(application rator rands)
          (cond
            [(application-hook rator rands (lambda (b) (remap b)))
             => (lambda (v) v)]
            [else
             ;; Any other application
             (application (remap rator) (map remap rands))])]
         [(branch tst thn els)
          (branch (remap tst) (remap thn) (remap els))]
         [(with-cont-mark key val body)
          (with-cont-mark (remap key) (remap val) (remap body))]
         [(beg0 forms)
          (beg0 (map remap forms))]
         [(seq forms)
          (seq (map remap forms))]
         [(varref toplevel dummy constant? unsafe?)
          (varref (remap toplevel) (remap dummy) constant? unsafe?)]
         [(assign id rhs undef-ok?)
          (assign (remap id) (remap rhs) undef-ok?)]
         [(apply-values proc args-expr)
          (apply-values (remap proc) (remap args-expr))]
         [(with-immed-mark key def-val body)
          (with-immed-mark (remap key) (remap def-val) (remap body))]
         [(case-lam name clauses)
          (case-lam name (map remap clauses))]
         [_
          (cond
            [(lam? b)
             (define tl-map (lam-toplevel-map b))
             (define new-tl-map
               (and tl-map
                    (for/set ([pos (in-set tl-map)])
                      (remap-toplevel-pos pos))))
             (struct-copy lam b
                          [body (remap (lam-body b))]
                          [toplevel-map new-tl-map])]
            [else b])])))))


(define (remap-names body
                     remap-name ; symbol -> symbol-or-import
                     #:application-hook [application-hook (lambda (rator rands remap) #f)])
  (for/list ([b (in-list body)])
    (let loop ([b b])
      (match b
        [`(define-values ,ids ,rhs)
         `(define-values ,(map remap-name ids) ,(loop rhs))]
        [`(lambda ,args ,body)
         `(lambda ,args ,(loop body))]
        [`(case-lambda [,argss ,bodys] ...)
         `(case-lambda ,@(for/list ([args (in-list argss)]
                                    [body (in-list bodys)])
                           `[,args ,(loop body)]))]
        [`(let-values ([,idss ,rhss] ...) ,body)
         `(let-values ,(for/list ([ids (in-list idss)]
                                  [rhs (in-list rhss)])
                         `[,ids ,(loop rhs)])
            ,(loop body))]
        [`(letrec-values ([,idss ,rhss] ...) ,body)
         `(letrec-values ,(for/list ([ids (in-list idss)]
                                     [rhs (in-list rhss)])
                            `[,ids ,(loop rhs)])
            ,(loop body))]
        [`(if ,tst ,thn ,els)
         `(if ,(loop tst) ,(loop thn) ,(loop els))]
        [`(begin . ,body)
         `(begin ,@(map loop body))]
        [`(begin0 ,e . ,body)
         `(begin0 ,(loop e) ,@(map loop body))]
        [`(set! ,id ,rhs)
         `(set! ,(remap-name id) ,(loop rhs))]
        [`(quote . _) b]
        [`(with-continuation-mark ,key ,val ,body)
         `(with-continuation-mark ,(loop key) ,(loop val) ,(loop body))]
        [`(#%variable-reference ,id)
         `(#%variable-reference ,(remap-name id))]
        [`(#%variable-reference . ,_) b]
        [`(,rator ,rands ...)
         (or (application-hook rator rands loop)
             `(,(loop rator) ,@(map loop rands)))]
        [_ (if (symbol? b)
               (remap-name b)
               b)]))))
