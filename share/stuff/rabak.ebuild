# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

inherit perl-module eutils

DESCRIPTION="rabak is a backup utility for files and databases based on rsync."
HOMEPAGE="http://www.raisin.de/rabak"
SRC_URI="http://www.raisin.de/rabak/stable/${P}.tgz"

SLOT="0"
LICENSE="MIT"
KEYWORDS="alpha amd64 ppc ppc64 sparc x86"
IUSE=""

RDEPEND=">=dev-lang/perl-5.8.2
		>=sys-apps/util-linux-2.12-r4
		>=sys-apps/coreutils-5.0.91-r4
		>=net-misc/openssh-3.7.1_p2-r1
		>=net-misc/rsync-2.6.0
		dev-perl/IPC-Run
		dev-perl/MailTools
		dev-perl/Digest-SHA1
		dev-perl/DBD-SQLite
		>=perl-core/Getopt-Long-2.36"

src_compile() {
	perl-module_src_prep
	perl-module_src_compile
}

src_install () {
	perl-module_src_install

	dodoc Licence.txt README TODO CHANGELOG

	# Move rsync to bin where it belongs.
	dobin rabak
	dodir /etc/rabak
	cp etc/* "${D}"/etc/rabak
	chmod 0400 "${D}"/etc/rabak/rabak.secret.cf
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
