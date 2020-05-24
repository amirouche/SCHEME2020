;;; The 'nil' configuration applies to all modes.
((scheme-mode . ((indent-tabs-mode . nil)
		 (tab-width . 2)
		 (eval . (progn
                           ;; nanopass framework
                           (put 'with-output-language 'scheme-indent-function 1)
                           (put 'nanopass-case 'scheme-indent-function 2)
                           ;; okvs
                           (put 'okvs-in-transaction 'scheme-indent-function 2)
                           (put 'engine-in-transaction 'scheme-indent-function 2)
			   ;; scheme
			   (put 'test-group 'scheme-indent-function 1)
			   (put 'switch 'scheme-indent-function 1)
			   (put 'test-equal 'scheme-indent-function 1)
			   (put 'call-with-input-string 'scheme-indent-function 1)
			   (put 'call-with-values 'scheme-indent-function 1)
			   ;; minikanren stuff
			   (put 'run* 'scheme-indent-function 1)
			   (put 'fresh 'scheme-indent-function 1)
			   (put 'conde 'scheme-indent-function nil)
			   (put 'run** 'scheme-indent-function 1)
			   ;; others
			   (put 'search-address-info 'scheme-indent-function 3)
			   (put 'call-with-lock 'scheme-indent-function 1)
			   (put 'call-with-port 'scheme-indent-function 1))))))
