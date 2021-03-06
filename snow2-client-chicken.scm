#! /bin/sh
#| -*- scheme -*-
exec csi -include-path /usr/local/share/scheme -s $0 "$@"
|#

(use r7rs)
;; (import-for-syntax r7rs)
(use srfi-69)
(require-library scheme.process-context)

(import (scheme base))

(include "srfi/60.sld")
(include "snow/assert.sld")
(include "snow/bytevector.sld")
(include "snow/binio.sld")
(include "snow/bignum.sld")
(include "snow/extio.sld")
(include "snow/filesys.sld")
(include "snow/digest.sld")
(include "snow/genport.sld")
(include "snow/zlib.sld")
(include "snow/tar.sld")
(include "seth/cout.sld")
(include "seth/deep-copy.sld")
(include "seth/xml/ssax.sld")
(include "seth/xml/sxpath.sld")
(include "seth/xml/sxml-serializer.sld")
(include "seth/string-read-write.sld")
(include "seth/uri.sld")
(include "seth/port-extras.sld")
(include "seth/network-socket.sld")
(include "seth/temporary-file.sld")
(include "seth/quoted-printable.sld")
(include "seth/base64.sld")
(include "seth/mime.sld")
(include "seth/http.sld")
(include "seth/crypt/hmac-sha-1.sld")
(include "seth/crypt/md5.sld")
(include "seth/aws/common.sld")
(include "seth/aws/s3.sld")
(include "seth/snow2/types.sld")
(include "seth/snow2/utils.sld")
(include "seth/snow2/r7rs-library.sld")
(include "seth/snow2/manage.sld")
(include "seth/snow2/client.sld")
(import (prefix (seth snow2 client) snow2-))

(snow2-main-program)
