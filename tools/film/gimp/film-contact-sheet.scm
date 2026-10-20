; Film Contact Sheet
; Builds a printable contact sheet from a folder of film strip scans.
; Appears under File > Create > Film Contact Sheet...
;
; Intended workflow (scans always at 300 dpi):
;   - 120 film:  4 strip scans, 3 exposures per strip -> 12 exposures
;   - 35mm film: strip scans of 6 exposures each
; Strips are placed at native scan size whenever they fit, so exposures
; print at their true physical size; the sheet is tagged 300 dpi.
; Strips are stacked top-to-bottom in filename order and centered.
; If the stack cannot fit the chosen paper, all strips are scaled down
; by the same factor so the sheet still holds every strip.

(define contact-sheet--dpi 300)
(define contact-sheet--margin 75)  ; 0.25 in at 300 dpi
(define contact-sheet--gap 24)     ; 2 mm between strips

(define (contact-sheet--sort-strings lst)
  (define (insert s sorted)
    (cond ((null? sorted) (list s))
          ((string<? s (car sorted)) (cons s sorted))
          (else (cons (car sorted) (insert s (cdr sorted))))))
  (let loop ((in lst) (out '()))
    (if (null? in) out (loop (cdr in) (insert (car in) out)))))

; file-glob returned (count (files...)) in GIMP 2; in GIMP 3 it returns
; ((files...)) — accept both shapes
(define (contact-sheet--glob pattern)
  (let ((r (file-glob pattern 1)))
    (if (and (pair? r) (number? (car r)))
        (cadr r)
        (car r))))

; stem is a glob prefix for the filename, e.g. "*" or "roll*"
(define (contact-sheet--scan-files dir stem)
  (let loop ((exts '("jpg" "JPG" "jpeg" "JPEG" "png" "PNG"
                     "tif" "TIF" "tiff" "TIFF" "bmp" "BMP" "webp" "WEBP"))
             (acc '()))
    (if (null? exts)
        (contact-sheet--sort-strings acc)
        (loop (cdr exts)
              (append acc
                      (contact-sheet--glob
                        (string-append dir "/" stem "." (car exts))))))))

(define (contact-sheet--basename path)
  (car (reverse (strbreakup path "/"))))

(define (contact-sheet--on? v)
  (not (or (eqv? v #f) (eqv? v 0))))

; rotate a scan to match a forced layout direction: "rows" wants strips
; lying down, "columns" wants strips standing up ("auto" never rotates)
(define (contact-sheet--orient src layout)
  (let ((w (car (gimp-image-get-width src)))
        (h (car (gimp-image-get-height src))))
    (cond ((and (string=? layout "rows") (> h w))
           (gimp-image-rotate src ROTATE-DEGREES270))
          ((and (string=? layout "columns") (> w h))
           (gimp-image-rotate src ROTATE-DEGREES90)))))

; paper-index: 0 = 8x10 inch, 1 = A4, 2 = Letter (all at 300 dpi, portrait)
(define (contact-sheet--paper paper-index)
  (cond ((= paper-index 1) (list 2480 3508))
        ((= paper-index 2) (list 2550 3300))
        (else              (list 2400 3000))))

; Builds and returns the new image, or #f when the folder has no scans.
; stem is a filename glob prefix such as "*" (dialog) or "roll*" (CLI).
; layout is "auto", "rows" (35mm: strips stacked top to bottom), or
; "columns" (120/620: strips side by side); rows/columns rotate scans
; into the needed orientation.
(define (film-contact-sheet-build-pattern dir stem paper-index invert black-paper layout)
  (let ((files (contact-sheet--scan-files dir stem)))
    (if (null? files)
        (begin
          (gimp-message
            "Film Contact Sheet: no image files found in that folder.")
          #f)
        (let* ((margin  contact-sheet--margin)
               (gap     contact-sheet--gap)
               (sources (map (lambda (f)
                               (let ((src (car (gimp-file-load
                                                 RUN-NONINTERACTIVE f))))
                                 (contact-sheet--orient src layout)
                                 src))
                             files))
               (dims    (map (lambda (src)
                               (list (car (gimp-image-get-width src))
                                     (car (gimp-image-get-height src))))
                             sources))
               ; strips scanned lying down are stacked as rows; strips
               ; scanned standing up are placed side by side as columns
               (n-portrait (apply + (map (lambda (d)
                                           (if (> (cadr d) (car d)) 1 0))
                                         dims)))
               (columns (cond ((string=? layout "columns") #t)
                              ((string=? layout "rows") #f)
                              (else (> (* 2 n-portrait) (length dims)))))
               (content-w (if columns
                              (+ (apply + (map car dims))
                                 (* gap (- (length dims) 1)))
                              (apply max (map car dims))))
               (content-h (if columns
                              (apply max (map cadr dims))
                              (+ (apply + (map cadr dims))
                                 (* gap (- (length dims) 1)))))
               (paper   (contact-sheet--paper paper-index))
               (pw      (car paper))
               (ph      (cadr paper))
               ; fit scale for portrait and landscape; prefer whichever
               ; needs less shrinking (ties go to portrait)
               (fit     (lambda (w h)
                          (min 1
                               (/ (- w (* 2 margin)) content-w)
                               (/ (- h (* 2 margin)) content-h))))
               (s-port  (fit pw ph))
               (s-land  (fit ph pw))
               (sheet-w (if (> s-land s-port) ph pw))
               (sheet-h (if (> s-land s-port) pw ph))
               (s       (max s-port s-land))
               (img     (car (gimp-image-new sheet-w sheet-h RGB)))
               (base    (car (gimp-layer-new img "Paper" sheet-w sheet-h
                                             RGB-IMAGE 100 LAYER-MODE-NORMAL))))
          (gimp-image-undo-disable img)
          (gimp-context-push)
          (gimp-context-set-defaults)
          (gimp-image-set-resolution img contact-sheet--dpi contact-sheet--dpi)

          (gimp-image-insert-layer img base 0 -1)
          (gimp-context-set-foreground
            (if (contact-sheet--on? black-paper) '(10 10 10) '(255 255 255)))
          (gimp-drawable-edit-fill base FILL-FOREGROUND)

          (let* ((sc (lambda (v) (max 1 (round (* v s)))))
                 (total-run (+ (apply + (map (lambda (d)
                                               (sc (if columns (car d) (cadr d))))
                                             dims))
                               (* gap (- (length dims) 1)))))
            (let loop ((srcs sources)
                       (ds dims)
                       (fs files)
                       (pos (if columns
                                (/ (- sheet-w total-run) 2)
                                (/ (- sheet-h total-run) 2))))
              (if (not (null? srcs))
                  (let* ((src   (car srcs))
                         (sw    (sc (car (car ds))))
                         (sh    (sc (cadr (car ds))))
                         (flat  (car (gimp-image-flatten src)))
                         (layer (car (gimp-layer-new-from-drawable flat img))))
                    (gimp-image-insert-layer img layer 0 -1)
                    (gimp-item-set-name layer (contact-sheet--basename (car fs)))
                    (if (< s 1)
                        (gimp-layer-scale layer sw sh FALSE))
                    (if (contact-sheet--on? invert)
                        (gimp-drawable-invert layer FALSE))
                    (if columns
                        (gimp-layer-set-offsets layer pos (/ (- sheet-h sh) 2))
                        (gimp-layer-set-offsets layer (/ (- sheet-w sw) 2) pos))
                    (gimp-image-delete src)
                    (loop (cdr srcs) (cdr ds) (cdr fs)
                          (+ pos (if columns sw sh) gap)))))
            (if (< s 1)
                (gimp-message
                  (string-append
                    "Film Contact Sheet: strips were scaled to "
                    (number->string (inexact->exact (round (* s 100))))
                    "% to fit the paper."))))

          (gimp-context-pop)
          (gimp-image-undo-enable img)
          img))))

(define (film-contact-sheet-build dir paper-index invert black-paper)
  (film-contact-sheet-build-pattern dir "*" paper-index invert black-paper "auto"))

(define (script-fu-film-contact-sheet dir paper-index invert black-paper layout-index)
  (let ((img (film-contact-sheet-build-pattern dir "*" paper-index invert black-paper
               (cond ((= layout-index 1) "rows")
                     ((= layout-index 2) "columns")
                     (else "auto")))))
    (if img
        (begin
          (gimp-display-new img)
          (gimp-displays-flush)))))

(script-fu-register-procedure "script-fu-film-contact-sheet"
  "Film Contact Sheet..."
  "Combine film strip scans from a folder into a printable 300 dpi contact sheet (120/620: strips side by side; 35mm: strips of 6 stacked)"
  "Claude"
  "2026"
  SF-DIRNAME "Folder of strip scans"                     ""
  SF-OPTION  "Paper size"                                '("8x10 inch" "A4" "Letter")
  SF-TOGGLE  "Invert strips (negative scans to positive)" TRUE
  SF-TOGGLE  "Black paper (darkroom look)"                TRUE
  SF-OPTION  "Strip layout"                              '("Auto" "Stacked rows (35mm)" "Side-by-side columns (120/620)")
)

(script-fu-menu-register "script-fu-film-contact-sheet"
                         "<Image>/File/Create")
