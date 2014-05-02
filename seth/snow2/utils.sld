(define-library (seth snow2 utils)
  (export get-repository
          read-repository
          get-repositories-and-siblings
          find-packages-with-library
          find-package-with-library
          snow2-package-libraries
          snow2-packages-libraries
          get-snow2-repo-name
          find-package-with-library
          find-packages-with-libraries
          gather-depends
          package-from-sexp
          package-from-filename
          get-library-manifest

          depend->sexp
          sibling->sexp
          library->sexp
          package->sexp
          repository->sexp
          refresh-package-from-filename
          find-libraries-by-name

          local-repository->in-fs-index-path
          local-repository->in-fs-index-filename
          local-repository->in-fs-tgz-path
          local-repository->in-fs-tgz-filename
          local-repository->in-fs-lib-path
          local-repository->in-fs-lib-filename
          )

  (import (scheme base)
          (scheme read)
          (scheme write)
          (scheme file)
          (scheme process-context))
  (cond-expand
   (chibi (import (only (srfi 1) filter make-list any fold last)))
   (else (import (srfi 1))))
  (cond-expand
   (chibi (import (chibi filesystem)))
   (else))
  (import (snow snowlib)
          (snow extio)
          ;; (snow srfi-13-strings)
          (seth srfi-69-hash-tables)
          (snow filesys)
          ;; (snow binio)
          ;; (snow genport)
          ;; (snow zlib)
          ;; (snow tar)
          (prefix (seth http) http-)
          ;; (seth temporary-file)
          ;; (seth string-read-write)
          ;; (seth srfi-37-argument-processor)
          (seth uri)
          (seth snow2 types)
          )

  (begin

    (define (depend-from-sexp depend-sexp)
      ;; depend-sexp will be a library name, like (snow snowlib)
      depend-sexp)

    (define (depend->sexp depend)
      depend)

    (define (sibling-from-sexp sibling-sexp)
      ;; siblings look like
      ;;
      ;; (sibling
      ;;  (name "Snow Base Repository")
      ;;  (url "http://snow-repository.s3-website-us-east-1.amazonaws.com/")
      ;;  (trust 1.0))
      ;;
      ;; we save the trust value, but don't currently do anything with it.
      (let ((name (get-string-by-type sibling-sexp 'name #f))
            (url (get-string-by-type sibling-sexp 'url #f))
            (trust (get-number-by-type sibling-sexp 'trust 0.5)))
        (make-snow2-sibling name (uri-reference url) trust)))

    (define (sibling->sexp sibling)
      `(sibling
        (name ,(snow2-sibling-name sibling))
        (url ,(uri->string (snow2-sibling-url sibling)))
        (trust ,(snow2-sibling-trust sibling))))


    (define (library-from-sexp library-sexp)
      ;; convert an s-exp into a library record
      (let ((name (get-list-by-type library-sexp 'name #f))
            (path (get-string-by-type library-sexp 'path #f))
            (depends-sexps (get-multi-args-by-type library-sexp 'depends '()))
            (version (get-string-by-type library-sexp 'version "1.0"))
            (homepage (get-args-by-type library-sexp 'homepage '()))
            (maintainers (get-args-by-type library-sexp 'maintainers '()))
            (authors (get-args-by-type library-sexp 'authors '()))
            (description (get-args-by-type library-sexp 'description '()))
            (license (get-args-by-type library-sexp 'license '()))
            )

        ;; (define (delist what)
        ;;   (cond ((and (list? what)
        ;;               (= (length what) 1))
        ;;          (delist (car what)))
        ;;         (else
        ;;          (list what))))

        (cond ((not name) #f)
              ((not path) #f)
              (else
               (make-snow2-library
                name path
                (map depend-from-sexp depends-sexps)
                version
                homepage
                maintainers
                authors
                description
                license
                #f)))))

    (define (library->sexp library)
      `(library
        (name ,(snow2-library-name library))
        (path ,(snow2-library-path library))
        (version ,(snow2-library-version library))
        (homepage ,@(snow2-library-homepage library))
        (maintainers ,@(snow2-library-maintainers library))
        (authors ,@(snow2-library-authors library))
        (description ,@(snow2-library-description library))
        (license ,@(snow2-library-license library))
        (depends ,@(map depend->sexp (snow2-library-depends library)))
        ))


    (define (package-from-sexp package-sexp)
      ;; convert a s-exp into a package record
      (let ((url (get-string-by-type package-sexp 'url #f))
            (name (get-list-by-type package-sexp 'name '()))
            (size (get-number-by-type package-sexp 'size 'unset))
            (checksum (get-list-by-type package-sexp 'checksum 'unset))
            (library-sexps (get-children-by-type package-sexp 'library)))
        (cond ((not url) #f)
              ((not name) #f)
              (else
               (let* ((libraries (map library-from-sexp library-sexps))
                      (package (make-snow2-package
                                name (uri-reference url) libraries #f
                                size checksum #f)))
                 ;; backlink to packages
                 (for-each
                  (lambda (library)
                    (set-snow2-library-package! library package))
                  libraries)
                 package)))))

    (define (package->sexp package)
      `(package
        (name ,(snow2-package-name package))
        (url ,(uri->string (snow2-package-url package)))
        ,@(let ((size (snow2-package-size package)))
            (if (not (eq? size 'unset)) `((size ,size)) '()))
        ,@(let ((checksum (snow2-package-checksum package)))
            (if (not (eq? checksum 'unset)) `((checksum ,checksum)) '()))
        ,@(map library->sexp (snow2-package-libraries package))))


    (define (package-from-filename package-filename)
      (let* ((package-port (open-input-file package-filename))
             (package-sexp (read package-port))
             (package (package-from-sexp package-sexp)))
        (close-input-port package-port)
        package))


    (define (repository-from-sexp repository-sexp)
      ;; convert an s-exp into a repository record
      (cond ((not (list? repository-sexp))
             (error "repository definition isn't a list." repository-sexp))
            ((null? repository-sexp)
             (error "repository s-exp is empty."))
            ((not (eq? (car repository-sexp) 'repository))
             (error "this doesn't look like a repository."))
            (else
             (let* ((package-sexps
                     (get-children-by-type repository-sexp 'package))
                    (packages (map package-from-sexp package-sexps))
                    (sibling-sexps
                     (get-children-by-type repository-sexp 'sibling))
                    (siblings (map sibling-from-sexp sibling-sexps))
                    (repo (make-snow2-repository siblings packages #f #f #f)))
               ;; backlink package to repository
               (for-each
                (lambda (package)
                  (set-snow2-package-repository! package repo))
                packages)
               repo))))


    (define (repository->sexp repository)
      `(repository
        ,@(map sibling->sexp (snow2-repository-siblings repository))
        ,@(map package->sexp (snow2-repository-packages repository))
        ))


    (define (read-repository in-port)
      ;; read an s-exp from in-port and convert it to a repository record.
      (let* ((repository-sexp
              (read
               (binary-port->textual-port in-port))))
        (repository-from-sexp repository-sexp)))


    (define (get-snow2-repo-name package)
      (cond ((and (list? (snow2-package-name package))
                  (not (null? (snow2-package-name package))))
             (snow2-package-name package))
            ((not (null? snow2-package-libraries))
             (let* ((lib (car (snow2-package-libraries package)))
                    (lib-name (snow2-library-name lib)))
               (cond ((and (list? lib-name)
                           (not (null? lib-name)))
                      (symbol->string (car lib-name)))
                     (else '()))))
            (else
             '())))


    (define (snow2-packages-libraries packages)
      ;; return a flattened list of all libraries in the given packages
      (fold
       (lambda (package lst)
         (append (snow2-package-libraries package) lst))
       '()
       packages))


    (define uri->hashtable-key uri->string)

    (define (package-contains-library? package library-name)
      ;; return #t if a package contains any libraries with the given name
      (let loop ((libraries (snow2-package-libraries package)))
        (cond ((null? libraries) #f)
              (else
               (let ((library (car libraries)))
                 ;; (write (snow2-library-name library))
                 ;; (display " VS ")
                 ;; (write library-name)
                 ;; (newline)
                 (if (equal? (snow2-library-name library) library-name)
                     #t
                     (loop (cdr libraries))))))))


    (define (find-packages-with-library repositories library-name)
      ;; find all packages with a library of the given name
      (let r-loop ((repositories repositories)
                   (candidate-packages '()))
        (cond
         ((null? repositories)
          (cond ((null? candidate-packages)
                 (error "couldn't find library" library-name))
                ;; XXX rather than just taking the last one,
                ;; select one based on version requirements, etc
                (else candidate-packages)))
         (else
          (let loop ((packages (snow2-repository-packages (car repositories)))
                     (candidate-packages candidate-packages))
            (cond ((null? packages)
                   (r-loop (cdr repositories)
                           candidate-packages))
                  (else
                   (let ((package (car packages)))
                     (if (package-contains-library? package library-name)
                         (loop (cdr packages)
                               (cons package candidate-packages))
                         (loop (cdr packages)
                               candidate-packages))))))))))


    (define (find-package-with-library repositories library-name)
      ;; find the last package that contains a library with the given name
      (car (find-packages-with-library repositories library-name)))


    (define (find-packages-with-libraries repositories library-names)
      ;; return a list of packages that contain any libraries
      ;; with the given library-names.
      (let ((package-url-ht (make-hash-table)))
        (for-each
         (lambda (library-name)
           (let ((package
                  (find-package-with-library repositories library-name)))
             (cond ((not package)
                    (error "didn't find a package with library: ~S\n"
                           library-name))
                   (else
                    (hash-table-set!
                     package-url-ht
                     (uri->hashtable-key (snow2-package-url package))
                     package)))))
         library-names)
        (hash-table-values package-url-ht)))


    (define (library-from-name repositories library-name)
      ;; search repositories for a library record with the given name.
      ;; return the first matching record or #f.
      (let* ((package (find-package-with-library repositories library-name)))
        (cond ((not package)
               (error
                "can't find package that contains ~S\n" library-name)
               #f)
              (else
               (let loop ((libraries (snow2-package-libraries package)))
                 (cond ((null? libraries) #f)
                       ((equal? library-name
                                (snow2-library-name (car libraries)))
                        (car libraries))
                       (else (loop (cdr libraries)))))))))


    (define (gather-depends repositories libraries)
      ;;
      ;; returns a list of snow2-packages
      ;;
      (let ((lib-name-ht (make-hash-table))
            (package-url-ht (make-hash-table)))
        (for-each
         (lambda (library)

           (let ((lib-name (snow2-library-name library)))
             (let ((package (find-package-with-library repositories lib-name)))
               (hash-table-set! lib-name-ht lib-name library)
               (hash-table-set!
                package-url-ht
                (uri->hashtable-key (snow2-package-url package))
                package))

             (for-each
              (lambda (depend)
                (let* ((package (find-package-with-library repositories depend))
                       (libs (snow2-package-libraries package)))
                  (hash-table-set!
                   package-url-ht
                   (uri->hashtable-key (snow2-package-url package))
                   package)
                  ;; XXX if the same lib is in more than one
                  ;; package, there should be some reason to pick one
                  ;; over the other?
                  (for-each
                   (lambda (lib)
                     (hash-table-set! lib-name-ht
                                      (snow2-library-name lib) lib))
                   libs)))
              (snow2-library-depends library))))
         libraries)

        (if (= (length (hash-table-keys lib-name-ht)) (length libraries))
            ;; nothing new added this pass, so we've finished.
            (hash-table-values package-url-ht)
            ;; we found more, go around again.
            (gather-depends repositories (hash-table-values lib-name-ht)))))


    (define (get-repository repository-url)
      (cond ((memq (uri-scheme repository-url) '(http https))
             ;; get repository over http
             (snow-with-exception-catcher
              (lambda (exn)
                (display "unable to fetch repository index: "
                         (current-error-port))
                (display (uri->string repository-url) (current-error-port))
                (newline (current-error-port))
                (display exn (current-error-port))
                (newline (current-error-port))
                #f)
              (lambda ()
                (let ((repository
                       (http-call-with-request-body
                        (uri->string repository-url)
                        read-repository)))
                  (set-snow2-repository-local! repository #f)
                  (set-snow2-repository-url! repository repository-url)
                  repository))))
            (else
             ;; read from local filesystem repository
             (let* ((repo-dirname (uri->string repository-url))
                    (tests-dirname (snow-make-filename repo-dirname "tests"))
                    (packages-dirname
                     (snow-make-filename repo-dirname "packages"))
                    (index-filename
                     (snow-make-filename repo-dirname "index.scm"))
                    )
               (cond ((or (not (snow-file-exists? tests-dirname))
                          (not (snow-file-directory? tests-dirname))
                          (not (file-exists? packages-dirname))
                          (not (snow-file-directory? packages-dirname))
                          (not (snow-file-exists? index-filename)))
                      #f)
                     (else
                      (let* ((in-port (open-binary-input-file index-filename))
                             (repository (read-repository in-port)))
                        (set-snow2-repository-local! repository #t)
                        (set-snow2-repository-url! repository repository-url)
                        (close-input-port in-port)
                        repository)))))))


    (define (get-repositories-and-siblings repositories repository-urls)
      (define (make-repo-has-url? url)
        (lambda (repository)
          (uri-equal? (snow2-repository-url repository) url)))
      (define (get-sibling-urls repository)
        (map snow2-sibling-url (snow2-repository-siblings repository)))
      (cond ((null? repository-urls) repositories)
            (else
             (let ((repository-url (car repository-urls)))
               (cond ((any (make-repo-has-url? repository-url) repositories)
                      ;; we've already loaded this one.
                      (get-repositories-and-siblings
                       repositories (cdr repository-urls)))
                     (else
                      ;; this was previously unloaded
                      (let ((repository (get-repository repository-url)))
                        (if repository
                            (let ((sibling-urls (get-sibling-urls repository)))
                              (get-repositories-and-siblings
                               (cons repository repositories)
                               (append (cdr repository-urls) sibling-urls)))
                            ;; perhaps this should be a fatal error.
                            ;; for now, just try to continue.
                            (get-repositories-and-siblings
                             repositories (cdr repository-urls))))))))))



    (define (get-library-manifest lib)
      ;; return a list of source files for a package
      (list
       (snow2-library-path lib)))


    (define (refresh-package-from-filename repository package-filename)
      ;; read a file that contains a package s-exp and update the copy
      ;; in repository.
      (let ((updated-package (package-from-filename package-filename)))
        (cond ((not updated-package)
               (error "can't read package metafile." package-filename)))
        (let loop ((repo-packages (snow2-repository-packages repository)))
          (cond ((null? repo-packages)
                 ;; we found a package file, but it's not in the repository's
                 ;; index.scm file.
                 (set-snow2-repository-packages!
                  repository
                  (cons updated-package
                        (snow2-repository-packages repository)))
                 updated-package)
                (else
                 (let ((repo-package (car repo-packages)))
                   (cond ((and
                           (equal? (snow2-package-name repo-package)
                                   (snow2-package-name updated-package))
                           (uri-equal?
                            (snow2-package-url repo-package)
                            (snow2-package-url updated-package)))
                          (cond ((not (snow2-packages-equal? repo-package
                                                             updated-package))
                                 ;; (display "package file changed.\n")
                                 (set-snow2-package-libraries!
                                  repo-package
                                  (snow2-package-libraries updated-package))
                                 (set-snow2-repository-dirty! repository #t)))
                          repo-package)
                         (else
                          (loop (cdr repo-packages))))))))))


    (define (find-libraries-by-name container library-name)
      ;; returns a (possibly empty) list of library structs that
      ;; have the given name and are somewhere inside container.
      ;; container can be any of:
      ;;   snow2-library, snow2-package, snow2-repository
      ;; or a list containing these.
      (if (snow2-library? container)
          (if (equal? library-name (snow2-library-name container))
              (list container)
              '())
          (fold append '()
                (map (lambda (child)
                       (find-libraries-by-name child library-name))
                     (cond ((snow2-package? container)
                            (snow2-package-libraries container))
                           ((snow2-repository? container)
                            (snow2-repository-packages container))
                           ((list? container) container)
                           (else
                            (error "unknown snow2 container type"
                                   container)))))))


    (define (local-repository->in-fs-index-path local-repository)
      ;; given an on-disk repository, return a path to index.scm
      (let* ((repo-path (uri-path (snow2-repository-url local-repository))))
        (append repo-path (list "index.scm"))))

    (define (local-repository->in-fs-index-filename local-repository)
      ;; given an on-disk repository, return the (perhaps relative)
      ;; path and filename of index.scm
      (snow-combine-filename-parts
       (local-repository->in-fs-index-path local-repository)))

    (define (local-repository->in-fs-tgz-path local-repository package)
      ;; within a local repository, return a path on the filesystem to
      ;; a tgz for the given package
      (let* ((repo-path (uri-path (snow2-repository-url local-repository)))
             (url (snow2-package-url package)))
        (reverse (cons (last (uri-path url)) (reverse repo-path)))))

    (define (local-repository->in-fs-tgz-filename local-repository package)
      ;; within a local repository, return a path/filename on the filesystem
      ;; to a tgz for the given package
      (snow-combine-filename-parts
       (local-repository->in-fs-tgz-path local-repository package)))


    (define (local-repository->in-fs-lib-path local-repository lib)
      ;; return path to library source file within a local repository
      (let* ((repo-path (uri-path (snow2-repository-url local-repository)))
             (in-pkg-lib-path (snow-split-filename (snow2-library-path lib))))
        (append repo-path in-pkg-lib-path)))

    (define (local-repository->in-fs-lib-filename local-repository lib)
      ;; return filename of library source file within a local repository
      (snow-combine-filename-parts
       (local-repository->in-fs-lib-path local-repository lib)))


    ))