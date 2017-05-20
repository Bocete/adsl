ADSL - Abstract Data Store Library
=========================================================

ADSL is a gem for formal verification of Ruby on Rails models.  Simply include it in your Gemfile, write a few 
invariants (rules) about ActiveRecord data that you wish to verify (for example, that at any given moment, every
Address has a User) and run `rake verify`!

Besides the verification algorithm, this tool includes a DSL for specifying invariants.  The syntax should feel
natural to any Rails user. Look at /examples.

This tool is distributed as a Ruby gem and is uploaded to [RubyGems.org] [1]. It requires Z3[2] and Spass[3] to run. Install
it and give it a try!


Installation
------------

This gem is tested on 64 bit Linux. OS-X compatibility not tested, give it a try
and tell us if it works! Windows is not supported at this moment.

 - Ruby 2.0.0 or later required, along with Rails 3.2.  The gem has limited support for 1.9.3 and Rails 4.  We suggest using the [Ruby Version Manager](https://rvm.io/rvm/install/) to manage this installation.
 - [Download and install Z3](https://github.com/Z3Prover/z3) and make sure its executable (`z3`) on your $PATH
 - [Download and install Spass](http://www.spass-prover.org/download/index.html) and make sure its executable (`SPASS`) on your $PATH
 - Install the ADSL gem by running `gem install adsl`.
   If you receive an error while generating documentation for 'activesupport' run `gem install rdoc adsl` instead.
 
Usage
-----

    rake verify <options>
    
Or, to just observe the extracted model,

    rake adsl_translate

The gem also adds an executable `adsl` that can be used for more fine tuned options.  Use `adsl --help` to look at options.

Development
-----------

### Source Repository

The ADSL gem is currently hosted at github. The github web page is http://github.com/Bocete/adsl.
You can download the source using our public git clone URL:

    git://github.com/Bocete/adsl.git

### Issues and Bug Reports

Feature requests and bug reports can be made at https://github.com/Bocete/adsl/issues

Publications
------------

* Ivan Bocic and Tevfik Bultan. "[Symbolic Model Extraction for Web Application Verification.](https://cs.ucsb.edu/~bo/papers/icse17.pdf)" ICSE 2017
* Ivan Bocic and Tevfik Bultan. "[Finding Access Control Bugs in Web Applications with CanCheck.](https://cs.ucsb.edu/~bo/papers/ase16.pdf)". ASE 2016
* Ivan Bocic and Tevfik Bultan. "[Efficient Data Model Verification with Many-Sorted Logic](https://cs.ucsb.edu/~bo/papers/ase15.pdf)". ASE 2015
* Ivan Bocic and Tevfik Bultan. "[Coexecutability for Efficient Verification of Data Model Updates.](https://cs.ucsb.edu/~bo/papers/icse15.pdf)". ICSE 2015
* Ivan Bocic and Tevfik Bultan. "[Data Model Bugs.](https://cs.ucsb.edu/~bo/papers/nfm15.pdf)". NFM 2015
* Ivan Bocic and Tevfik Bultan. "[Inductive Verification of Data Model Invariants for Web Applications.](https://www.cs.ucsb.edu/~bo/papers/icse14.pdf)". ICSE 2014

License
-------

Rake is available under a [Lesser GPL (LGPL) license](LICENSE).


Warranty
--------

This software is provided "as is" and without any express or
implied warranties, including, without limitation, the implied
warranties of merchantibility and fitness for a particular
purpose.

  [1]: https://rubygems.org/gems/adsl "RubyGems.org"
  [2]: https://github.com/Z3Prover/z3 "The Z3 Theorem Prover"
  [3]: http://www.spass-prover.org/ "Spass"
