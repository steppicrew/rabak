
# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

inherit perl-app eutils

DESCRIPTION="rabak is a backup utility for files and databases based on rsync."
HOMEPAGE="http://www.raisin.de/rabak"
SRC_URI="http://www.raisin.de/rabak/stable/${PF}.tar.gz"

SLOT="0"
LICENSE="Artistic"
KEYWORDS="alpha amd64 ppc ppc64 sparc x86"
IUSE="wui"

RDEPEND=">=dev-lang/perl-5.8.2
		>=sys-apps/util-linux-2.12-r4
		>=sys-apps/coreutils-5.0.91-r4
		>=net-misc/openssh-3.7.1_p2-r1
		>=net-misc/rsync-2.6.0
		dev-perl/IPC-Run
		dev-perl/Data-UUID
		dev-perl/MailTools
		dev-perl/Digest-SHA
		dev-perl/DBD-SQLite
		wui? ( dev-perl/JSON-XS )
		>=perl-core/Getopt-Long-2.36"

src_compile() {
	cd "${WORKDIR}/${PF}"

	perl-module_src_prep
	perl-module_src_compile
}

src_install () {
	cd "${WORKDIR}/${PF}"

	perl-module_src_install

	dodoc LICENSE README TODO CHANGELOG INSTALL

	# Move rabak to bin where it belongs.
	dobin rabak
	# TODO: install wui if USE wui is set
	# if use wui; then
	# fi
	# Copy sample config files
	insinto /etc
	doins -r etc/rabak
	# Make raba.secret.cf readable only for root
	fperms 0400 "/etc/rabak/rabak.secret.cf"
	# Copy misc files
	insinto "/usr/share/${PF}"
	doins -r share/*
}

pkg_postinst() {
	elog
	elog "The configuration file: /etc/rabak/rabak.sample.cf "
	elog "  has been installed. "
	elog "This is a template. "
	elog "Copy, or move, the above file to: /etc/rabak/rabak.cf "
	elog "Note that upgrading will update the template, not real config. "
	elog
	elog "Please pay special attention to permissions of "
	elog "  /etc/rabak/rabak.secret.cf"
	elog
}
