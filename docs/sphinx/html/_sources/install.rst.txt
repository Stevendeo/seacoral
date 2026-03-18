How to install
==============

Install with :code:`opam`
-------------------------

If :code:`seacoral` is available in your opam repository, you can just call::

  opam install seacoral

Build and install with :code:`dune`
-----------------------------------

Checkout the sources of :code:`seacoral` in a directory.

You need a switch with at least version :code:`4.14.2` of OCaml::
  
  opam switch create 4.14.2

Then, you need to install all the dependencies::

  opam install --deps-only .

Finally, you can build the package and install it::

  eval $(opam env)
  dune build
  dune install

Note that a :code:`Makefile` is provided, it contains the following
targets:

* :code:`build`: build the code
* :code:`install`: install the generated files
* :code:`build-deps`: install opam dependencies
* :code:`sphinx`: build sphinx documentation (from the :code:`sphinx/` directory)
* :code:`dev-deps`: build development dependencies, in particular
  :code:`ocamlformat`, :code:`odoc` and :code:`merlin`
* :code:`odoc`: build documentation with :code:`odoc`
* :code:`fmt`: format the code using :code:`ocamlformat`
* :code:`test`: run tests
