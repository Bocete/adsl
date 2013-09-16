ADSL - Abstract Data Store Library
=========================================================

ADSL is a gem for formal verification of Ruby on Rails models.  Simply include it in your Gemfile, write a few 
invariants (rules) about ActiveRecord data that you wish to verify (for example, that at any given moment, every
Address has a User) and run `rake verify`!

Besides the verification algorithm, this tool includes a DSL for specifying invariants.  The syntax should feel
natural to any Rails user. Look at /examples.

This tool is distributed as a Ruby gem and is uploaded to [RubyGems.org] [2]. It requires Spass[1] to run. Install
it and give it a try!


Installation
------------

This gem is tested on 32 and 64 bit Linux. OS-X compatibility not tested, give it a try
and tell us if it works! Windows is not supported at this moment.

 - Ruby 1.9.3 or later required, along with Rails 3.2.  We suggest using the [Ruby Version Manager](https://rvm.io/rvm/install/) to manage this installation.
 - [Download and install Spass](http://www.spass-prover.org/download/index.html) and make sure its executable (`bin/SPASS`) on your $PATH
 - Install the ADSL gem by running `gem install adsl`.
   If you receive an error while generating documentation for 'activesupport' run `gem install rdoc adsl` instead.
 
Usage
-----

    rake verify <options>
    
Or, to just observe the extracted model,

    rake adsl_translate

Development
-----------

### Source Repository

The ADSL gem is currently hosted at github. The github web page is http://github.com/Bocete/adsl.
You can download the source using our public git clone URL:

    git://github.com/Bocete/adsl.git

### Issues and Bug Reports

Feature requests and bug reports can be made at https://github.com/Bocete/adsl/issues


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
