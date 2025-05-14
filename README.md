## manylinux for our packages

Based on https://github.com/pypa/manylinux.

Adaptations:

- keep python static libraries so we can use them during the build
- install all dependencies to the image for Valhalla (`valhalla_python` branch) and OSRM (`osrm-python` branch)
- install `protobuf == 21.1` (last before the `abseil` debacle), but not sure anymore why.. might be a relic from early days..

Don't try to build locally, it's very painful and CI caches properly, so it shouldn't take forever.
