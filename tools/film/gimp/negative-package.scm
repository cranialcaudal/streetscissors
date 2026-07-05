; Negative Package
; Combines up to 3 photos, converted to negatives, onto a single
; filmstrip-style frame. Appears under File > Create > Negative Package...
;
; Leave Photo 2 / Photo 3 empty to use fewer than 3 photos.

(define (negative-package--nonempty lst)
  (cond ((null? lst) '())
        ((and (string? (car lst)) (> (string-length (car lst)) 0))
         (cons (car lst) (negative-package--nonempty (cdr lst))))
        (else (negative-package--nonempty (cdr lst)))))

(define (negative-package--on? v)
  (not (or (eqv? v #f) (eqv? v 0))))

; Builds and returns the new image, or #f when no photo files were given.
(define (negative-package-build file1 file2 file3 frame-h border film-look)
  (let ((files (negative-package--nonempty (list file1 file2 file3))))
    (if (null? files)
        (begin
          (gimp-message "Negative Package: choose at least one photo file.")
          #f)
        (let* ((frame-h (round frame-h))
               (border  (round border))
               (sources (map (lambda (f)
                               (car (gimp-file-load RUN-NONINTERACTIVE f)))
                             files))
               ; scale every photo to the frame height, keeping aspect ratio
               (widths  (map (lambda (src)
                               (let ((w (car (gimp-image-get-width src)))
                                     (h (car (gimp-image-get-height src))))
                                 (max 1 (round (/ (* w frame-h) h)))))
                             sources))
               (total-w (+ border (apply + (map (lambda (w) (+ w border)) widths))))
               (total-h (+ frame-h (* 2 border)))
               (img  (car (gimp-image-new total-w total-h RGB)))
               (base (car (gimp-layer-new img "Film base" total-w total-h
                                          RGB-IMAGE 100 LAYER-MODE-NORMAL))))
          (gimp-image-undo-disable img)
          (gimp-context-push)
          (gimp-context-set-defaults)

          (gimp-image-insert-layer img base 0 -1)
          (gimp-context-set-foreground '(16 14 12))
          (gimp-drawable-edit-fill base FILL-FOREGROUND)

          (let loop ((srcs sources) (ws widths) (x border))
            (if (not (null? srcs))
                (let* ((src   (car srcs))
                       (sw    (car ws))
                       (flat  (car (gimp-image-flatten src)))
                       (layer (car (gimp-layer-new-from-drawable flat img))))
                  (gimp-image-insert-layer img layer 0 -1)
                  (gimp-layer-scale layer sw frame-h FALSE)
                  (gimp-drawable-invert layer FALSE)
                  (gimp-layer-set-offsets layer x border)
                  (gimp-image-delete src)
                  (loop (cdr srcs) (cdr ws) (+ x sw border)))))

          (if (negative-package--on? film-look)
              (let* ((hole-h (max 8  (round (* border 0.42))))
                     (hole-w (max 10 (round (* border 0.5))))
                     (pitch  (* hole-w 2))
                     (count  (inexact->exact
                               (truncate (/ (- total-w hole-w) pitch))))
                     (x0     (round (/ (- total-w (+ (* count pitch) hole-w)) 2)))
                     (ty     (round (/ (- border hole-h) 2)))
                     (by     (+ (- total-h border) ty)))
                (gimp-selection-none img)
                (let hloop ((i 0))
                  (if (<= i count)
                      (let ((x (+ x0 (* i pitch))))
                        (gimp-image-select-rectangle img CHANNEL-OP-ADD
                                                     x ty hole-w hole-h)
                        (gimp-image-select-rectangle img CHANNEL-OP-ADD
                                                     x by hole-w hole-h)
                        (hloop (+ i 1)))))
                (gimp-context-set-foreground '(245 245 245))
                (gimp-drawable-edit-fill base FILL-FOREGROUND)
                (gimp-selection-none img)))

          (gimp-context-pop)
          (gimp-image-undo-enable img)
          img))))

(define (script-fu-negative-package file1 file2 file3 frame-h border film-look)
  (let ((img (negative-package-build file1 file2 file3 frame-h border film-look)))
    (if img
        (begin
          (gimp-display-new img)
          (gimp-displays-flush)))))

(script-fu-register-procedure "script-fu-negative-package"
  "Negative Package..."
  "Combine up to 3 photos, converted to negatives, on a single filmstrip frame"
  "Claude"
  "2026"
  SF-FILENAME   "Photo 1"                          ""
  SF-FILENAME   "Photo 2 (optional)"               ""
  SF-FILENAME   "Photo 3 (optional)"               ""
  SF-ADJUSTMENT "Frame height (px)"                '(600 100 4000 10 100 0 1)
  SF-ADJUSTMENT "Border / spacing (px)"            '(48 16 400 2 10 0 1)
  SF-TOGGLE     "Filmstrip look (sprocket holes)"  TRUE
)

(script-fu-menu-register "script-fu-negative-package"
                         "<Image>/File/Create")
