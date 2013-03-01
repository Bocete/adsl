ADSL - Abstract Data Store Language Parser and Translator
=========================================================

This package contains adsl, a Ruby gem for verifying ADSL specifications.

Installation
------------

**Note:** This gem does not include Spass. You need to have Spass installed and on your PATH. Download Spass 

 - This tool requires Ruby 1.8.7. This specific version is required by the libraries we use
 - [Download and install Spass](http://www.spass-prover.org/download/index.html) and put its executable (`bin/SPASS`) on your $PATH
 - Install the `adsl` gem by running `gem install adsl`.
   You may receive an error while generating documentation for `activesupport`. You can fix it by running `gem install rdoc` and installing `adsl` once again.

**Platform compatibility:** This gem is developed and tested on 64 bit Linux. 32 bit Linux and OS-X compatibility not tested, give it a try and tell us if it works! Windows incompatible at this moment.


Usage
-----

    adsl-verify <specification-file>

For options and other modes of operation, run

    adsl-verify --help
  
Development
-----------

### Source Repository

The ADSL gem is currently hosted at github. The github web page is
http://github.com/Bocete/adsl. The public git clone URL is

    git://github.com/Bocete/adsl.git

### Issues and Bug Reports

Feature requests and bug reports can be made here

    https://github.com/Bocete/adsl/issues

License
-------

Rake is available under a [Lesser GPL (LGPL) license](LICENSE).

Warranty
--------

This software is provided "as is" and without any express or
implied warranties, including, without limitation, the implied
warranties of merchantibility and fitness for a particular
purpose.
