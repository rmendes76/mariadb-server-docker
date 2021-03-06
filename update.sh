#!/bin/bash
set -eo pipefail

defaultSuite='bionic'
declare -A suites=(
	[5.5]='trusty'
	[10.0]='xenial'
)

declare -A dpkgArchToBashbrew=(
	[amd64]='amd64'
	[armel]='arm32v5'
	[armhf]='arm32v7'
	[arm64]='arm64v8'
	[i386]='i386'
	[ppc64el]='ppc64le'
	[s390x]='s390x'
)

getRemoteVersion() {
	local version="$1"; shift # 10.3
	local suite="$1"; shift # bionic
	local dpkgArch="$1" shift # arm64

	echo "$(
		curl -fsSL "http://downloads.mariadb.com/MariaDB/mariadb-$MARIADB_MAJOR/repo/ubuntu/dists/$suite/main/binary-$dpkgArch/Packages" 2>/dev/null  \
			| tac|tac \
			| awk -F ': ' '$1 == "Package" { pkg = $2; next } $1 == "Version" && pkg == "mariadb-server-'"$version"'" { print $2; exit }'
	)"
}

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

travisEnv=
for version in "${versions[@]}"; do
	suite="${suites[$version]:-$defaultSuite}"
	fullVersion="$(getRemoteVersion "$version" "$suite" 'amd64')"
	if [ -z "$fullVersion" ]; then
		echo >&2 "warning: cannot find $version in $suite"
		continue
	fi

	arches=
	sortedArches="$(echo "${!dpkgArchToBashbrew[@]}" | xargs -n1 | sort | xargs)"
	for arch in $sortedArches; do
		if ver="$(getRemoteVersion "$version" "$suite" "$arch")" && [ -n "$ver" ]; then
			arches="$arches ${dpkgArchToBashbrew[$arch]}"
		fi
	done


	cp Dockerfile.template "$version/Dockerfile"
if [ "$backup" == 'mariadb-backup' ] && [[ "$version" < 10.3 ]]; then
		# 10.1 and 10.2 have mariadb major version in the package name
		backup="$backup-$version"
	fi

	(
		set -x
		cp docker-entrypoint.sh "$version/"
		sed -i \
			-e 's!%%MARIADB_VERSION%%!'"$fullVersion"'!g' \
			-e 's!%%MARIADB_MAJOR%%!'"$version"'!g' \
			-e 's!%%SUITE%%!'"$suite"'!g' \
			-e 's!%%BACKUP_PACKAGE%%!'"$backup"'!g' \
			-e 's!%%ARCHES%%!'"$arches"'!g' \
			"$version/Dockerfile"
	)

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
