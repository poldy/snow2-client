(define-library (seth deep-copy)
  (export deep-copy)
  (import (scheme base)
          (scheme char))
  (begin
    (define (deep-copy x)
      (cond ((number? x) x)
            ((symbol? x) x)
            ((char? x) x)
            ((boolean? x) x)
            ((string? x) (string-copy x))
            ((pair? x) (cons (deep-copy (car x)) (deep-copy (cdr x))))
            ((null? x) '())
            ((vector? x) (vector-map deep-copy x))
            ((bytevector? x) (bytevector-copy x))
            (else
             (error "deep-copy found unexpected type" x))))))
