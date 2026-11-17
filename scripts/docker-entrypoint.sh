#!/bin/bash
# Entry point of the kratos-tester image.
#
# If a problemtype is mounted at /src/kratos.gid (read-only is fine), it is
# copied to /gid/problemtypes/kratos.gid so the tester never writes into the
# mounted checkout. Otherwise the problemtype already in the image is used.
#
# Example (from the KratosTester folder):
#   docker run --rm \
#     -v <GiDInterface>/kratos.gid:/src/kratos.gid:ro \
#     -v ./output:/app/output \
#     -e CASES=dem_2d_circledrop_write,dam_3d_thermomechanics_write \
#     kratos-tester
set -e

if [ -d /src/kratos.gid ]; then
    echo "Using problemtype mounted at /src/kratos.gid"
    rm -rf /gid/problemtypes/kratos.gid
    cp -r /src/kratos.gid /gid/problemtypes/kratos.gid
    # A Windows checkout may have CRLF in the Linux launch scripts; CI (Linux checkout) has LF
    find /gid/problemtypes/kratos.gid/exec -name '*.unix.bat' -exec sed -i 's/\r$//' {} +
fi
chmod -R a+rwx /gid/problemtypes/kratos.gid/exec

cd /app
exec node scripts/runAllCases.js "$@"
