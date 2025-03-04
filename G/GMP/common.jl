# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

function configure(version)
    name = "GMP"

    hash = Dict(
        v"6.1.2" => "5275bb04f4863a13516b2f39392ac5e272f5e1bb8057b18aec1c9b79d73d8fb2",
        v"6.2.0" => "f51c99cb114deb21a60075ffb494c1a210eb9d7cb729ed042ddb7de9534451ea",
        v"6.2.1" => "eae9326beb4158c386e39a356818031bd28f3124cf915f8c5b1dc4c7a36b4d7c",
    )

    # Collection of sources required to complete build
    sources = [
        ArchiveSource("https://gmplib.org/download/gmp/gmp-$(version).tar.bz2", hash[version]),
        DirectorySource("./bundled"; follow_symlinks=true),
    ]

    # Bash recipe for building across all platforms
    script = raw"""
cd $WORKSPACE/srcdir/gmp-*

# Include Julia-carried patches
for f in $WORKSPACE/srcdir/patches/*.patch; do
    echo "Applying patch ${f}"
    atomic_patch -p1 ${f}
done

flags=(--enable-cxx --enable-shared --disable-static)

# On x86_64 architectures, build fat binary
if [[ ${proc_family} == intel ]]; then
    flags+=(--enable-fat)
fi

if [[ ${bb_full_target} == *-sanitize+memory* ]]; then
    # Install msan runtime (for clang)
    cp -rL ${libdir}/linux/* /opt/x86_64-linux-musl/lib/clang/*/lib/linux/
fi
autoreconf
./configure --prefix=$prefix --build=${MACHTYPE} --host=${target} ${flags[@]}

make -j${nproc}
make install

# On Windows, we need to make sure that the non-versioned dll names exist too
if [[ ${target} == *mingw* ]]; then
    cp -v ${libdir}/libgmp-*.dll "${libdir}/libgmp.dll"
    cp -v ${libdir}/libgmpxx-*.dll "${libdir}/libgmpxx.dll"
fi

# GMP is dual-licensed, install all license files
install_license COPYING*
"""

    # We enable experimental platforms as this is a core Julia dependency
    platforms = expand_cxxstring_abis(supported_platforms(;experimental=true))
    push!(platforms, Platform("x86_64", "linux"; sanitize="memory"))
    products = [
        LibraryProduct("libgmp", :libgmp),
        LibraryProduct("libgmpxx", :libgmpxx),
    ]

    # Dependencies that must be installed before this package can be built
    dependencies = [
        BuildDependency("LLVMCompilerRT_jll",platforms=[Platform("x86_64", "linux"; sanitize="memory")]),
    ]

    return name, version, sources, script, platforms, products, dependencies
end

