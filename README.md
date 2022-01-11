## manylinux for our packages

Based on https://github.com/pypa/manylinux.

Adaptations:

- keep python static libraries so we can use them during the build
- install all dependencies to the image for Valhalla (`valhalla_python` branch) and OSRM (`osrm-python` branch)
