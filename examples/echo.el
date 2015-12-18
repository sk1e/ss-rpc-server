(require 'ss-rpc-client)


(setq example-server (ss:start-server
                        "example"
                        (format "%s %s"
                                "~/racket/bin/racket" ;; path to your racket executable
                                (expand-file-name
                                 "echo.rkt"
                                 (file-name-directory buffer-file-name)))))


(ss:call example-server 'echo 2)


(ss:terminate! example-server)


