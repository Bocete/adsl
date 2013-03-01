ADSL - Abstract Data Store Language Parser and Translator
=========================================================

This tool an Abstract Data Store Language (ADSL) specification verification tool.

ADSL is a language for specifying Abstract Data Stores using a syntax familiar to anyone that has experience
with ORM tools such as Hibernate and ActiveRecord. A specification contains the model classes, actions executed
using a RESTful interface, and a set of invariants to be verified.

This tool verifies a specification by translating it into a first order logic theorem verifiable by [Spass] [1],
a theorem prover. It provides detailed information on the actions and invariants verified in human-readable or
CSV format.

This tool is distributed as a Ruby gem and is uploaded to [RubyGems.org] [2]. Install it and give it a try!


Installation
------------

This gem is tested on 32 and 64 bit Linux. OS-X compatibility not tested, give it a try
and tell us if it works! Windows is not supported at this moment.

 - Install Ruby 1.8.7. This specific version is required by the libraries we use. We suggest using the
   [Ruby Version Manager](https://rvm.io/rvm/install/) to manage this installation.
 - [Download and install Spass](http://www.spass-prover.org/download/index.html) and make sure its 
   executable (`bin/SPASS`) on your $PATH
 - Install the ADSL gem by running `gem install adsl`.
   
   If you receive an error while generating documentation for 'activesupport' run `gem install rdoc adsl` instead.
 - Test the installation by verifying [the example specification](https://raw.github.com/Bocete/adsl/master/example/running-example.adsl)

Usage
-----

    adsl-verify <specification-file>

For options and other modes of operation, run

    adsl-verify --help

You can download sample ADSL specifications 


Development
-----------

### Source Repository

The ADSL gem is currently hosted at github. The github web page is http://github.com/Bocete/adsl.
You can download the source using our public git clone URL:

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

  [1]: http://www.spass-prover.org/ "Spass"
  [2]: https://rubygems.org/gems/adsl "RubyGems.org"
