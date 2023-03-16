# LUMI-tools

Some tools that go in the lumi-tools module.

-   lumi-quota: Shows the quota of a user read directly from Lustre.

-   lumi-workspaces: Shows the quota and remaining allocations of a user using
    lumi-quota and lumi-allocations.

A manual page for lumi-allocations, which is maintained in a separate repository, is
also included.

## Installation process

The installation process is designed to be easy to incorporate into EasyBuild.

The first make target and the one that will be chosen without argument will create
a `build` subdirectory and build a recommended set of tools, which is basically copying
and renaming files. 

For some tools we may switch to an entirely different implementation over time and for this
reason we have an installation process that can be extended to keep the old versions available
under a different name, or in an alternate `bin` directory should the need arise.

The `install` target will then install all tools gathered in the `build` subdirectory in
the installation directory indicated by the `PREFIX` variable (which defaults to `/usr/local`
which would produce an error on LUMI).
