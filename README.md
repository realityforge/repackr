# Repackr

This repository is the home to a set of scripts that are used to publish pre-release
versions of open source libraries as maven artifacts. The goal of the project is to
make it easy to use more modern versions of these libraries without relying on `SNAPSHOT`
versions even if the open source libraries have long release cycles or do not normally
release maven artifacts.

Current projects included in this cycle and their associated tasks are:

    $ buildr elemental2:local_release  # Download the latest elemental2 project and push a local release
    $ buildr elemental2:release        # Download the latest elemental2 project and push a release to Maven Central

### On Naming and Versioning

The artifacts are named the same as the artifacts in the original source projects except
that the group is prefixed with `org.realityforge.` and the version scheme is different and
usually based on build number.
